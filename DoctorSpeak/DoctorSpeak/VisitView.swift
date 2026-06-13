import SwiftUI
import SwiftData

struct VisitView: View {
    @Bindable var appointment: Appointment
    @State private var recorder = AudioRecorder()
    @State private var errorMessage: String?
    /// The transcript text that existed before the current recording session started.
    /// New session text is appended after this so prior recordings are retained.
    @State private var baseTranscript = ""

    private var hasTranscript: Bool { !appointment.visit_transcript.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            transcriptArea
            Divider()
            controlArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.96, green: 0.98, blue: 1.0).ignoresSafeArea())
        .navigationTitle("Visit")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: recorder.sessionTranscript) { _, session in
            // Mirror the live session transcript into the saved transcript, preserving the base.
            if baseTranscript.isEmpty {
                appointment.visit_transcript = session
            } else if session.isEmpty {
                appointment.visit_transcript = baseTranscript
            } else {
                appointment.visit_transcript = baseTranscript + "\n\n" + session
            }
        }
    }

    // MARK: - Transcript display

    @ViewBuilder
    private var transcriptArea: some View {
        if hasTranscript || recorder.isRecording {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !appointment.visit_transcript.isEmpty {
                            Text(appointment.visit_transcript)
                                .font(.system(size: 16))
                                .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !recorder.partialTranscript.isEmpty {
                            Text(recorder.partialTranscript)
                                .font(.system(size: 16))
                                .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2).opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(20)
                }
                .onChange(of: appointment.visit_transcript) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: recorder.partialTranscript) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        } else {
            Spacer()
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlArea: some View {
        VStack(spacing: 8) {
            if recorder.isRecording {
                Button(action: stopRecording) {
                    controlLabel(icon: "stop.circle.fill", title: "Stop Recording", color: .red, pulse: true)
                }
            } else {
                Button(action: startRecording) {
                    controlLabel(
                        icon: "microphone.circle.fill",
                        title: hasTranscript ? "Continue Recording Visit" : "Record Visit",
                        color: Color(red: 0.11, green: 0.49, blue: 0.78),
                        pulse: false
                    )
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white)
    }

    private func controlLabel(icon: String, title: String, color: Color, pulse: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: pulse)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2))
        }
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func startRecording() {
        // Snapshot whatever is already saved so the new session appends to it.
        baseTranscript = appointment.visit_transcript
        Task {
            do {
                try await recorder.startRecording()
                errorMessage = nil
            } catch {
                errorMessage = "Could not start recording: \(error.localizedDescription)"
            }
        }
    }

    private func stopRecording() {
        recorder.stopRecording()
    }
}
