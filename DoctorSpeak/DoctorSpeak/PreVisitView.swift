import SwiftUI
import SwiftData

struct PreVisitView: View {
    @Bindable var appointment: Appointment
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appointment.previsit_messages.sorted(by: { $0.timestamp < $1.timestamp })) { message in
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
                .onChange(of: appointment.previsit_messages.count) {
                    if let last = appointment.previsit_messages.last {
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
        .navigationTitle(appointment.appointment_title.isEmpty ? "New Appointment" : appointment.appointment_title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard appointment.previsit_messages.isEmpty else { return }
            appointment.previsit_messages.append(ChatMessage(text: "What type of doctor are you seeing?", isUser: false))
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appointment.previsit_messages.append(ChatMessage(text: trimmed, isUser: true))
        inputText = ""
        isLoading = true

        let snapshot = appointment.previsit_messages

        Task {
            do {
                let raw = try await GrokService.chat(messages: snapshot, prompt: createPrevisitPrompt())
                let data = Data(raw.utf8)
                let parsed = try JSONDecoder().decode(PrevisitResponse.self, from: data)
                appointment.previsit_messages.append(ChatMessage(text: parsed.message, isUser: false))
                if !parsed.appointmentTitle.isEmpty {
                    appointment.appointment_title = parsed.appointmentTitle
                }
            } catch {
                appointment.previsit_messages.append(ChatMessage(text: "Sorry, I couldn't connect. Please try again.", isUser: false))
            }
            isLoading = false
        }
    }
}

struct LoadingBubble: View {
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    DotView(delay: Double(i) * 0.2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            Spacer(minLength: 48)
        }
        .id("loading")
    }
}

struct DotView: View {
    let delay: Double
    @State private var opacity: Double = 0.3

    var body: some View {
        Circle()
            .frame(width: 8, height: 8)
            .foregroundStyle(Color(red: 0.11, green: 0.49, blue: 0.78))
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay)) {
                    opacity = 1.0
                }
            }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 48) }

            Text(message.text)
                .font(.system(size: 16))
                .foregroundStyle(message.isUser ? .white : Color(red: 0.1, green: 0.15, blue: 0.2))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.isUser
                        ? Color(red: 0.11, green: 0.49, blue: 0.78)
                        : .white
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)

            if !message.isUser { Spacer(minLength: 48) }
        }
        .id(message.id)
    }
}

#Preview {
    @Previewable @State var appt = Appointment()
    NavigationStack {
        PreVisitView(appointment: appt)
    }
    .modelContainer(for: Appointment.self, inMemory: true)
}
