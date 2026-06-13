import AVFoundation

@MainActor
@Observable
class AudioRecorder {
    private var audioEngine = AVAudioEngine()
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioConverter: AVAudioConverter?
    private var shouldRecord = false

    private(set) var isRecording = false
    /// Live interim text (plain, no speaker labels) — updates rapidly while speaking
    private(set) var partialTranscript = ""
    /// Full speaker-labeled transcript for the current recording session.
    /// Rebuilt from all confirmed words each time a final chunk arrives.
    private(set) var sessionTranscript = ""

    /// Finalized utterances for this session, in order, with each word's speaker
    /// index. Committed only from utterance-final (`speech_final == true`) events,
    /// which carry the diarizer's full-context (corrected) speaker labels.
    private var committedWords: [(speaker: Int, text: String)] = []
    /// Words for the utterance currently in progress, gathered from chunk-final
    /// (`is_final == true, speech_final == false`) events. These carry the
    /// diarizer's early, low-context labels, so they are replaced by the
    /// stitched utterance-final result rather than committed directly.
    private var currentUtteranceWords: [(speaker: Int, text: String)] = []

    private static let targetSampleRate: Double = 16000
    private static let wsURL = URL(string: "wss://api.x.ai/v1/stt?sample_rate=16000&encoding=pcm&interim_results=true&language=en&diarize=true")!

    func startRecording() async throws {
        shouldRecord = true

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Reset session state
        partialTranscript = ""
        sessionTranscript = ""
        committedWords = []
        currentUtteranceWords = []

        try await openWebSocket()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: true
        )!
        audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.audioConverter else { return }
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * Self.targetSampleRate / inputFormat.sampleRate)
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }
            var error: NSError?
            var inputConsumed = false
            converter.convert(to: converted, error: &error) { _, outStatus in
                if inputConsumed { outStatus.pointee = .noDataNow; return nil }
                outStatus.pointee = .haveData
                inputConsumed = true
                return buffer
            }
            guard error == nil, converted.frameLength > 0,
                  let channelData = converted.int16ChannelData else { return }
            let data = Data(bytes: channelData[0], count: Int(converted.frameLength) * 2)
            Task { @MainActor [weak self] in
                try? await self?.webSocketTask?.send(.data(data))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stopRecording() {
        shouldRecord = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false)
        isRecording = false
        partialTranscript = ""

        // Signal completion; server sends final transcript.done then closes.
        let ws = webSocketTask
        webSocketTask = nil
        Task {
            try? await ws?.send(.string(#"{"type":"audio.done"}"#))
            ws?.cancel(with: .normalClosure, reason: nil)
        }
    }

    // MARK: - WebSocket lifecycle

    private func openWebSocket() async throws {
        var request = URLRequest(url: Self.wsURL)
        request.setValue("Bearer \(GROK_API_KEY)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        try await waitForReady()
        startReceiving(on: task)
    }

    /// Reopen the socket if it drops while the user still wants to record.
    /// Confirmed words persist across reconnects so no transcribed text is lost.
    private func reconnectIfNeeded() async {
        guard shouldRecord else { return }
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard shouldRecord else { return }
        do {
            try await openWebSocket()
        } catch {
            await reconnectIfNeeded()
        }
    }

    private func waitForReady() async throws {
        guard let task = webSocketTask else { return }
        let message = try await task.receive()
        if case .string(let text) = message,
           let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["type"] as? String == "transcript.created" { return }
    }

    private func startReceiving(on task: URLSessionWebSocketTask) {
        Task { [weak self] in
            guard let self else { return }
            while true {
                guard let message = try? await task.receive() else { break }
                guard case .string(let text) = message,
                      let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String else { continue }

                switch type {
                case "transcript.partial":
                    let isFinal = json["is_final"] as? Bool ?? false
                    let speechFinal = json["speech_final"] as? Bool ?? false
                    if isFinal {
                        let words = Self.parseWords(from: json)
                        if speechFinal {
                            // Utterance final: the complete, stitched utterance with
                            // the diarizer's full-context speaker labels. This is the
                            // source of truth — it supersedes the tentative chunk-final
                            // words gathered for this utterance (which had stale,
                            // low-context labels), so commit it and reset the buffer.
                            self.committedWords += words.isEmpty ? self.currentUtteranceWords : words
                            self.currentUtteranceWords = []
                        } else {
                            // Chunk final: tentative words for the in-progress utterance.
                            // Held separately so a later utterance-final can replace them.
                            self.currentUtteranceWords += words
                        }
                        self.partialTranscript = ""
                        self.rebuildSessionTranscript()
                    } else {
                        // Interim — live preview only.
                        self.partialTranscript = json["text"] as? String ?? ""
                    }

                case "transcript.done":
                    // Flush any in-progress utterance that never received a
                    // speech_final (e.g. the user stopped mid-sentence).
                    if !self.currentUtteranceWords.isEmpty {
                        self.committedWords += self.currentUtteranceWords
                        self.currentUtteranceWords = []
                    }
                    self.partialTranscript = ""
                    self.rebuildSessionTranscript()

                default:
                    break
                }
            }
            // Socket closed. Reconnect if the user hasn't pressed stop.
            if self.webSocketTask === task { self.webSocketTask = nil }
            await self.reconnectIfNeeded()
        }
    }

    // MARK: - Diarization parsing

    /// The speaker field is documented as an integer, but parse defensively
    /// in case it arrives as a Double or String.
    private static func speakerIndex(_ word: [String: Any]) -> Int? {
        if let i = word["speaker"] as? Int { return i }
        if let d = word["speaker"] as? Double { return Int(d) }
        if let s = word["speaker"] as? String { return Int(s) }
        return nil
    }

    /// Parse the `words` array of a final `transcript.partial` event into
    /// `(speaker, text)` pairs. Speaker defaults carry forward within this event
    /// only — never across events — so a missing label can't leak a stale
    /// speaker from a previous utterance.
    private static func parseWords(from json: [String: Any]) -> [(speaker: Int, text: String)] {
        var result: [(speaker: Int, text: String)] = []
        if let words = json["words"] as? [[String: Any]], !words.isEmpty {
            var lastSpeaker = 0
            for word in words {
                let speaker = speakerIndex(word) ?? lastSpeaker
                lastSpeaker = speaker
                let text = (word["text"] as? String)
                    ?? (word["word"] as? String)
                    ?? (word["punctuated_word"] as? String)
                    ?? ""
                if !text.isEmpty {
                    result.append((speaker, text))
                }
            }
        } else if let text = json["text"] as? String, !text.isEmpty {
            // Fallback: no word-level data available — emit as a single block.
            result.append((0, text))
        }
        return result
    }

    /// Group consecutive words by speaker into "Speaker N: ..." paragraphs.
    private func rebuildSessionTranscript() {
        var result = ""
        var currentSpeaker: Int? = nil
        var chunk = ""
        for word in committedWords + currentUtteranceWords {
            if word.speaker != currentSpeaker {
                if let prev = currentSpeaker, !chunk.isEmpty {
                    result += "Speaker \(prev + 1): \(chunk.trimmingCharacters(in: .whitespaces))\n\n"
                }
                currentSpeaker = word.speaker
                chunk = word.text + " "
            } else {
                chunk += word.text + " "
            }
        }
        if let last = currentSpeaker, !chunk.isEmpty {
            result += "Speaker \(last + 1): \(chunk.trimmingCharacters(in: .whitespaces))"
        }
        sessionTranscript = result
    }
}
