import SwiftUI
import SwiftData

struct VisitView: View {
    @Bindable var appointment: Appointment
    @State private var recorder = AudioRecorder()
    @State private var errorMessage: String?
    /// The transcript text that existed before the current recording session started.
    /// New session text is appended after this so prior recordings are retained.
    @State private var baseTranscript = ""
    /// True while Grok is generating the patient-facing visit summary.
    @State private var isSummarizing = false

    private enum VisitTab { case summary, transcript }
    @State private var selectedTab: VisitTab = .summary

    private var hasTranscript: Bool { !appointment.visit_transcript.isEmpty }
    private var hasSummary: Bool { !appointment.visit_summary.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if recorder.isRecording {
                recordingView
            } else {
                if hasSummary {
                    tabBar
                    if selectedTab == .summary {
                        summaryArea
                    } else {
                        transcriptArea
                    }
                } else {
                    transcriptArea
                }
                Divider()
                controlArea
            }
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
            // Once Grok speech-to-text has produced the final transcript, summarize
            // the full visit for the patient.
            if !session.isEmpty {
                summarizeVisit()
            }
        }
    }

    // MARK: - Summary / Transcript tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "Summary", tab: .summary)
            tabButton(title: "Transcript", tab: .transcript)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(.white)
    }

    private func tabButton(title: String, tab: VisitTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected
                    ? Color(red: 0.11, green: 0.49, blue: 0.78)
                    : Color(red: 0.1, green: 0.15, blue: 0.2).opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? Color(red: 0.11, green: 0.49, blue: 0.78) : .clear)
                        .frame(height: 2)
                }
        }
    }

    private var summaryArea: some View {
        ScrollView {
            Text(appointment.visit_summary)
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }

    // MARK: - Transcript display

    @ViewBuilder
    private var transcriptArea: some View {
        if hasTranscript || recorder.isRecording || recorder.isTranscribing {
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

    // MARK: - Recording

    /// While recording, a large centered Stop button with the live transcript
    /// scrolling by underneath it.
    private var recordingView: some View {
        VStack(spacing: 28) {
            Spacer()

            Button(action: stopRecording) {
                VStack(spacing: 14) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, isActive: true)
                    Text("Stop Recording")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2))
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !appointment.visit_transcript.isEmpty {
                            Text(appointment.visit_transcript)
                                .font(.system(size: 16))
                                .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2).opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !recorder.partialTranscript.isEmpty {
                            Text(recorder.partialTranscript)
                                .font(.system(size: 16))
                                .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 20)
                }
                .onChange(of: recorder.partialTranscript) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .frame(maxHeight: 240)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlArea: some View {
        VStack(spacing: 8) {
            if recorder.isTranscribing || isSummarizing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(recorder.isTranscribing ? "Generating final transcript…" : "Summarizing the visit…")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2))
                }
                .padding(.vertical, 18)
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
            if let message = recorder.errorMessage ?? errorMessage {
                Text(message)
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

    /// Sends the full visit transcript to Grok chat to produce a plain-language
    /// summary for the patient, stored on the appointment for the post-visit view.
    private func summarizeVisit() {
        let transcript = appointment.visit_transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        isSummarizing = true
        Task {
            defer { isSummarizing = false }
            do {
                let summary = try await GrokService.summarizeVisit(transcript: transcript)
                appointment.visit_summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                selectedTab = .summary
            } catch {
                errorMessage = "Couldn't summarize the visit: \(error.localizedDescription)"
            }
        }
    }
}
