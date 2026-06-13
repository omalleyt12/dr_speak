import SwiftUI
import SwiftData

/// Voice-driven version of `PreVisitView`. The Grok voice agent asks the
/// intake questions out loud; its speech appears as assistant chat bubbles in
/// real time, and the patient's spoken replies appear as user bubbles.
struct VoicePreVisitView: View {
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
                        ForEach(appointment.previsit_messages.sorted(by: { $0.timestamp < $1.timestamp })) { message in
                            MessageBubble(message: message)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 8)
                }
                .onChange(of: appointment.previsit_messages.count) {
                    if let last = appointment.previsit_messages.last {
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
        .onDisappear {
            stopAgent()
            generateTitleIfNeeded()
        }
    }

    /// When leaving pre-visit, if the appointment still has no title, ask Grok
    /// to name it from the conversation in the background.
    private func generateTitleIfNeeded() {
        guard appointment.appointment_title.isEmpty else { return }
        let messages = appointment.previsit_messages
        guard !messages.isEmpty else { return }
        let appointment = self.appointment
        Task {
            if let title = try? await GrokService.generateTitle(messages: messages) {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    appointment.appointment_title = trimmed
                }
            }
        }
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
        let agent = GrokVoiceAgent(instructions: createPrevisitVoicePrompt(profile: profiles.first))

        agent.onUserTranscript = { transcript in
            appointment.previsit_messages.append(ChatMessage(text: transcript, isUser: true))
        }
        agent.onAssistantResponseStarted = {
            let message = ChatMessage(text: "", isUser: false)
            streamingMessage = message
            appointment.previsit_messages.append(message)
        }
        agent.onAssistantTranscriptDelta = { delta in
            streamingMessage?.text += delta
        }
        agent.onAssistantResponseDone = {
            // Discard empty placeholder bubbles if no transcript arrived.
            if let message = streamingMessage,
               message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appointment.previsit_messages.removeAll { $0.id == message.id }
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
        VoicePreVisitView(appointment: appt)
    }
    .modelContainer(for: Appointment.self, inMemory: true)
}
