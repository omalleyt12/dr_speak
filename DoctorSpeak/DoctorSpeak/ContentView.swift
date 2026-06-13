import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var newAppointment: Appointment? = nil
    @State private var showUpcomingAppointments = false
    @State private var showPastAppointments = false

    var body: some View {
        NavigationStack {
        ZStack {
            Color(red: 0.94, green: 0.97, blue: 1.0)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image("DoctorSpeakLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        .padding(.top, 48)

                    Text("Doctor Speak")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Your medical companion")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.11, green: 0.49, blue: 0.78), Color(red: 0.05, green: 0.67, blue: 0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                // Buttons
                VStack(spacing: 16) {
                    AppointmentButton(
                        title: "New Appointment",
                        icon: "plus.circle.fill",
                        color: Color(red: 0.11, green: 0.49, blue: 0.78),
                        action: startNewAppointment
                    )

                    AppointmentButton(
                        title: "Upcoming Appointments",
                        icon: "calendar",
                        color: Color(red: 0.11, green: 0.49, blue: 0.78),
                        action: { showUpcomingAppointments = true }
                    )
                    .navigationDestination(isPresented: $showUpcomingAppointments) {
                        UpcomingAppointmentsView()
                    }

                    AppointmentButton(
                        title: "Past Appointments",
                        icon: "clock.fill",
                        color: Color(red: 0.05, green: 0.67, blue: 0.72),
                        action: { showPastAppointments = true }
                    )
                    .navigationDestination(isPresented: $showPastAppointments) {
                        PastAppointmentsView()
                    }
                }
                .padding(24)

                Spacer()
            }
        }
            .navigationDestination(item: $newAppointment) { appt in
                VoicePreVisitView(appointment: appt)
            }
        } // NavigationStack
    }

    private func startNewAppointment() {
        let appt = Appointment()
        modelContext.insert(appt)
        APPOINTMENTS.append(appt)
        newAppointment = appt
    }
}

struct AppointmentButton: View {
    let title: String
    let icon: String
    let color: Color
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) { label }
    }

    private var label: some View {
        HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)
                    .frame(width: 44)

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    ContentView()
}
