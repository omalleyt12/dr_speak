import SwiftUI
import SwiftData

struct AppointmentDetailView: View {
    @Bindable var appointment: Appointment

    var body: some View {
        VStack(spacing: 16) {
            NavigationLink(destination: VoicePreVisitView(appointment: appointment)) {
                AppointmentPhaseButton(title: "Pre-visit", icon: "list.clipboard.fill", color: Color(red: 0.11, green: 0.49, blue: 0.78))
            }
            NavigationLink(destination: VisitView(appointment: appointment)) {
                AppointmentPhaseButton(title: "Visit", icon: "stethoscope", color: Color(red: 0.05, green: 0.67, blue: 0.72))
            }
            NavigationLink(destination: PostVisitView(appointment: appointment)) {
                AppointmentPhaseButton(title: "Post-visit", icon: "checkmark.circle.fill", color: Color(red: 0.2, green: 0.6, blue: 0.4))
            }
            Spacer()
        }
        .padding(24)
        .background(Color(red: 0.94, green: 0.97, blue: 1.0).ignoresSafeArea())
        .navigationTitle("Appointment")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppointmentPhaseButton: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
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
