import AVFoundation
import Speech

enum RecorderError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone and Speech Recognition permissions are required."
        case .recognizerUnavailable:
            return "Speech recognition is not available on this device right now."
        }
    }
}

/// Records the visit while showing a live, on-device transcript via Apple's
/// `SFSpeechRecognizer`. When recording stops, the full captured audio is sent
/// to Grok for a higher-quality final transcript, which replaces the live one.
@MainActor
@Observable
class AudioRecorder {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    private(set) var isRecording = false
    /// True while the final Grok transcription is in flight after stopping.
    private(set) var isTranscribing = false

    /// Live, on-device (Apple) transcript shown while recording. Cleared once the
    /// final transcript is ready.
    private(set) var partialTranscript = ""
    /// Final transcript for the current recording session, produced by Grok after
    /// the user stops. The view mirrors this into the saved visit transcript.
    private(set) var sessionTranscript = ""
    private(set) var errorMessage: String?

    // MARK: - Permissions

    private func requestPermissions() async -> Bool {
        let micGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        return micGranted && speechStatus == .authorized
    }

    // MARK: - Recording lifecycle

    func startRecording() async throws {
        guard await requestPermissions() else { throw RecorderError.permissionDenied }
        guard let recognizer, recognizer.isAvailable else { throw RecorderError.recognizerUnavailable }

        // Reset session state.
        partialTranscript = ""
        sessionTranscript = ""
        errorMessage = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Write captured audio to a WAV file (format matches the tap buffers, so
        // no conversion is needed) for the final Grok transcription on stop.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("visit-\(UUID().uuidString).wav")
        let file = try AVAudioFile(
            forWriting: url,
            settings: inputFormat.settings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )
        audioFile = file
        recordingURL = url

        // Apple on-device live recognition.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor in self.partialTranscript = text }
        }

        // Single tap feeds both the live recognizer and the recording file.
        // Capture locals so the audio-thread closure doesn't touch actor state.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            request.append(buffer)
            try? file.write(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioFile = nil // closes the file
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false

        guard let url = recordingURL else { return }
        recordingURL = nil

        // Keep the on-device transcript as a fallback if Grok fails.
        let appleTranscript = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        isTranscribing = true

        Task {
            defer {
                isTranscribing = false
                partialTranscript = ""
                try? FileManager.default.removeItem(at: url)
            }
            do {
                let final = try await GrokService.transcribe(audioURL: url)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                sessionTranscript = final.isEmpty ? appleTranscript : final
            } catch {
                sessionTranscript = appleTranscript
                if !appleTranscript.isEmpty {
                    errorMessage = "Couldn't reach Grok for the final transcript — showing the on-device version."
                } else {
                    errorMessage = "Transcription failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
