import AVFoundation
import Foundation

/// Real-time, full-duplex voice agent backed by xAI's Grok Realtime API
/// (`wss://api.x.ai/v1/realtime`, OpenAI Realtime-compatible).
///
/// Captures microphone audio, streams it to Grok, plays back the model's
/// speech, and surfaces live transcripts of both sides of the conversation
/// through closures so the UI can render chat bubbles.
@MainActor
@Observable
class GrokVoiceAgent {
    // MARK: - Observable state
    private(set) var isConnected = false
    private(set) var isActive = false
    /// True while the assistant is currently speaking.
    private(set) var assistantSpeaking = false

    // MARK: - Callbacks (always invoked on the main actor)
    /// A finalized user utterance (transcribed speech).
    var onUserTranscript: ((String) -> Void)?
    /// The assistant started a new spoken response.
    var onAssistantResponseStarted: (() -> Void)?
    /// A streamed chunk of the assistant's current spoken response.
    var onAssistantTranscriptDelta: ((String) -> Void)?
    /// The assistant finished its current spoken response.
    var onAssistantResponseDone: (() -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - Audio
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var captureConverter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    /// Suppresses mic capture during assistant playback to prevent echo feedback.
    private let micGate = MicGate()

    private static let sampleRate: Double = 24000
    /// Format we send to / receive from the API: PCM16 mono @ 24 kHz.
    private let wireFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: GrokVoiceAgent.sampleRate,
        channels: 1,
        interleaved: true
    )!
    /// Float32 mono @ 24 kHz format used to drive the player node.
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: GrokVoiceAgent.sampleRate,
        channels: 1,
        interleaved: false
    )!

    // MARK: - WebSocket
    private var webSocketTask: URLSessionWebSocketTask?
    /// Maps conversation item id -> role ("user" / "assistant") so transcripts
    /// can be attributed to the correct speaker.
    private var itemRoles: [String: String] = [:]
    private static let url = URL(string: "wss://api.x.ai/v1/realtime?model=grok-voice-latest")!

    private let instructions: String

    init(instructions: String) {
        self.instructions = instructions
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard !isActive else { return }
        isActive = true
        try await openWebSocket()
        try startAudio()
    }

    func stop() {
        isActive = false
        assistantSpeaking = false
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        micGate.reset()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let ws = webSocketTask
        webSocketTask = nil
        isConnected = false
        ws?.cancel(with: .normalClosure, reason: nil)
    }

    // MARK: - WebSocket

    private func openWebSocket() async throws {
        var request = URLRequest(url: Self.url)
        request.setValue("Bearer \(GROK_API_KEY)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        isConnected = true
        startReceiving(on: task)
        try await configureSession()
        // Kick off the conversation so the agent greets the patient first.
        send(["type": "response.create"])
    }

    private func configureSession() async throws {
        let config: [String: Any] = [
            "type": "session.update",
            "session": [
                "voice": "eve",
                "instructions": instructions,
                "turn_detection": ["type": "server_vad"],
                "audio": [
                    "input": ["format": ["type": "audio/pcm", "rate": Int(Self.sampleRate)]],
                    "output": ["format": ["type": "audio/pcm", "rate": Int(Self.sampleRate)]]
                ]
            ]
        ]
        send(config)
    }

    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        Task { [weak self] in
            try? await self?.webSocketTask?.send(.string(text))
        }
    }

    private func startReceiving(on task: URLSessionWebSocketTask) {
        Task { [weak self] in
            while true {
                guard let message = try? await task.receive() else { break }
                guard let self else { break }
                switch message {
                case .string(let text):
                    self.handleEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleEvent(text)
                    }
                @unknown default:
                    break
                }
            }
            if let self, self.webSocketTask === task {
                self.isConnected = false
            }
        }
    }

    private func handleEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "response.output_audio.delta", "response.audio.delta":
            if let b64 = json["delta"] as? String ?? json["audio"] as? String {
                playAudioChunk(base64: b64)
            }

        case "response.output_audio_transcript.delta", "response.audio_transcript.delta", "response.text.delta":
            if let delta = json["delta"] as? String, !delta.isEmpty {
                if !assistantSpeaking {
                    assistantSpeaking = true
                    onAssistantResponseStarted?()
                }
                onAssistantTranscriptDelta?(delta)
            }

        case "response.output_audio_transcript.done", "response.audio_transcript.done", "response.text.done", "response.done":
            if assistantSpeaking {
                assistantSpeaking = false
                onAssistantResponseDone?()
            }

        case "conversation.item.created", "conversation.item.added":
            // Remember each item's role so we can be certain a transcript
            // belongs to the user (and not the assistant) before showing it.
            if let item = json["item"] as? [String: Any],
               let id = item["id"] as? String,
               let role = item["role"] as? String {
                itemRoles[id] = role
            }

        case "conversation.item.input_audio_transcription.completed":
            // Only the user's own speech belongs in the right-hand bubbles.
            // Input-audio transcription is user input by definition, but guard
            // against any item we explicitly know to be the assistant.
            let itemId = json["item_id"] as? String
            let role = itemId.flatMap { itemRoles[$0] }
            guard role == "user" || role == nil else { break }
            if let transcript = json["transcript"] as? String,
               !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onUserTranscript?(transcript)
            }

        case "error":
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Voice agent error"
            onError?(msg)

        default:
            break
        }
    }

    // MARK: - Audio capture & playback

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)

        let inputNode = engine.inputNode
        // Enable Apple's voice-processing (acoustic echo cancellation) so the
        // agent doesn't transcribe its own playback.
        try? inputNode.setVoiceProcessingEnabled(true)

        let inputFormat = inputNode.outputFormat(forBus: 0)
        captureConverter = AVAudioConverter(from: inputFormat, to: wireFormat)
        playbackConverter = AVAudioConverter(from: wireFormat, to: playbackFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleCaptureBuffer(buffer, inputFormat: inputFormat)
        }

        engine.prepare()
        try engine.start()
        playerNode.play()
    }

    private func handleCaptureBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        // Half-duplex: don't send mic audio while the assistant is speaking,
        // otherwise its playback echoes back and gets transcribed as the user.
        if micGate.shouldSuppressMic { return }
        guard let converter = captureConverter else { return }
        let ratio = Self.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: capacity) else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData
            consumed = true
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.int16ChannelData else { return }
        let data = Data(bytes: channel[0], count: Int(out.frameLength) * 2)
        let b64 = data.base64EncodedString()
        send(["type": "input_audio_buffer.append", "audio": b64])
    }

    private func playAudioChunk(base64: String) {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { return }
        let frameCount = AVAudioFrameCount(data.count / 2)
        guard frameCount > 0,
              let pcm16 = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: frameCount) else { return }
        pcm16.frameLength = frameCount
        data.withUnsafeBytes { raw in
            if let src = raw.baseAddress, let dst = pcm16.int16ChannelData {
                memcpy(dst[0], src, data.count)
            }
        }

        guard let converter = playbackConverter,
              let floatBuffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount) else { return }
        var error: NSError?
        var consumed = false
        converter.convert(to: floatBuffer, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData
            consumed = true
            return pcm16
        }
        guard error == nil, floatBuffer.frameLength > 0 else { return }

        micGate.bufferScheduled()
        playerNode.scheduleBuffer(floatBuffer) { [weak self] in
            self?.micGate.bufferFinished()
        }
        if !playerNode.isPlaying { playerNode.play() }
    }
}

/// Thread-safe gate that suppresses microphone capture while the assistant is
/// playing back audio, plus a short grace period afterward. This keeps the
/// conversation half-duplex so Grok's own speech (leaking from the speaker into
/// the mic) is never streamed back and mis-transcribed as the user talking.
///
/// Accessed from the real-time audio capture thread, the playback completion
/// thread, and the main actor, so all state is protected by a lock.
final class MicGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeBuffers = 0
    private var resumeTime: CFAbsoluteTime = 0
    /// How long after playback drains to keep the mic muted (lets room echo die down).
    private let gracePeriod: CFAbsoluteTime = 0.4

    func bufferScheduled() {
        lock.lock(); activeBuffers += 1; lock.unlock()
    }

    func bufferFinished() {
        lock.lock()
        activeBuffers = max(0, activeBuffers - 1)
        if activeBuffers == 0 {
            resumeTime = CFAbsoluteTimeGetCurrent() + gracePeriod
        }
        lock.unlock()
    }

    /// True while the assistant is speaking (or just finished) — drop mic audio.
    var shouldSuppressMic: Bool {
        lock.lock(); defer { lock.unlock() }
        if activeBuffers > 0 { return true }
        return CFAbsoluteTimeGetCurrent() < resumeTime
    }

    func reset() {
        lock.lock(); activeBuffers = 0; resumeTime = 0; lock.unlock()
    }
}
