import SwiftUI
import SwiftData

struct PostVisitView: View {
    @Bindable var appointment: Appointment
    @Query private var profiles: [PatientProfile]
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appointment.postvisit_messages.sorted(by: { $0.timestamp < $1.timestamp })) { message in
                            MessageBubble(message: message)
                        }
                        if isLoading {
                            LoadingBubble()
                                .id("loading")
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
                .onChange(of: isLoading) {
                    if isLoading {
                        withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button(action: {}) {
                    Image(systemName: "microphone.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.11, green: 0.49, blue: 0.78))
                        .frame(width: 36, height: 36)
                }

                TextField("Type a message…", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.94, green: 0.97, blue: 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .focused($inputFocused)
                    .onSubmit(sendMessage)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
                                ? Color.gray.opacity(0.4)
                                : Color(red: 0.11, green: 0.49, blue: 0.78)
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.white)
        }
        .background(Color(red: 0.96, green: 0.98, blue: 1.0))
        .navigationTitle(appointment.appointment_title.isEmpty ? "Post-visit" : appointment.appointment_title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard appointment.postvisit_messages.isEmpty else { return }
            appointment.postvisit_messages.append(ChatMessage(text: appointment.visit_summary, isUser: false))
            appointment.postvisit_messages.append(ChatMessage(text: "Do you have any questions or concerns about your visit?", isUser: false))
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appointment.postvisit_messages.append(ChatMessage(text: trimmed, isUser: true))
        inputText = ""
        isLoading = true

        let snapshot = appointment.postvisit_messages

        Task {
            do {
                let raw = try await GrokService.chat(messages: snapshot, prompt: createPostvisitPrompt(transcript: appointment.visit_transcript, profile: profiles.first))
                let parsed = try JSONDecoder().decode(PostvisitResponse.self, from: Data(raw.utf8))
                appointment.postvisit_messages.append(ChatMessage(text: parsed.message, isUser: false))
            } catch {
                appointment.postvisit_messages.append(ChatMessage(text: "Sorry, I couldn't connect. Please try again.", isUser: false))
            }
            isLoading = false
        }
    }
}

#Preview {
    @Previewable @State var appt = Appointment()
    NavigationStack {
        PostVisitView(appointment: appt)
    }
    .modelContainer(for: Appointment.self, inMemory: true)
}
