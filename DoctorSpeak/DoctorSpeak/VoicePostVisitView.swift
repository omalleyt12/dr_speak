import SwiftUI
import SwiftData

/// Voice-driven version of `PostVisitView`. The Grok voice agent opens by
/// reading the visit summary aloud and asking the patient if they have any
/// questions or concerns; its speech appears as assistant chat bubbles in real
/// time, and the patient's spoken replies appear as user bubbles.
struct VoicePostVisitView: View {
    @Bindable var appointment: Appointment
    @Query private var profiles: [PatientProfile]

    @State private var agent: GrokVoiceAgent?
    @State private var isActive = false
    @State private var errorMessage: String?
    /// The assistant bubble currently being streamed (built up from deltas).
    @State private var streamingMessage: ChatMessage?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appointment.postvisit_messages.sorted(by: { $0.timestamp < $1.timestamp })) { message in
                            MessageBubble(message: message)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 8)
                }
                .onChange(of: appointment.postvisit_messages.count) {
                    if let last = appointment.postvisit_messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: streamingMessage?.text) {
                    if let id = streamingMessage?.id {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            VStack(spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button(action: toggle) {
                    VStack(spacing: 10) {
                        Image(systemName: isActive ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(isActive ? .red : Color(red: 0.11, green: 0.49, blue: 0.78))
                            .symbolEffect(.pulse, isActive: isActive)
                        Text(isActive ? "Tap to end voice chat" : "Tap to start voice chat")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2))
                    }
                }
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity)
            .background(.white)
        }
        .background(Color(red: 0.96, green: 0.98, blue: 1.0))
        .navigationTitle(appointment.appointment_title.isEmpty ? "New Appointment" : appointment.appointment_title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stopAgent() }
    }

    private func toggle() {
        if isActive {
            stopAgent()
        } else {
            startAgent()
        }
    }

    private func startAgent() {
        errorMessage = nil
        let agent = GrokVoiceAgent(instructions: createPostvisitVoicePrompt(summary: appointment.visit_summary, profile: profiles.first))

        agent.onUserTranscript = { transcript in
            appointment.postvisit_messages.append(ChatMessage(text: transcript, isUser: true))
        }
        agent.onAssistantResponseStarted = {
            let message = ChatMessage(text: "", isUser: false)
            streamingMessage = message
            appointment.postvisit_messages.append(message)
        }
        agent.onAssistantTranscriptDelta = { delta in
            streamingMessage?.text += delta
        }
        agent.onAssistantResponseDone = {
            // Discard empty placeholder bubbles if no transcript arrived.
            if let message = streamingMessage,
               message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appointment.postvisit_messages.removeAll { $0.id == message.id }
            }
            streamingMessage = nil
        }
        agent.onError = { message in
            errorMessage = message
        }

        self.agent = agent
        isActive = true

        Task {
            do {
                try await agent.start()
            } catch {
                errorMessage = "Couldn't start voice chat: \(error.localizedDescription)"
                isActive = false
                self.agent = nil
            }
        }
    }

    private func stopAgent() {
        agent?.stop()
        agent = nil
        streamingMessage = nil
        isActive = false
    }
}

#Preview {
    @Previewable @State var appt = Appointment()
    NavigationStack {
        VoicePostVisitView(appointment: appt)
    }
    .modelContainer(for: Appointment.self, inMemory: true)
}
