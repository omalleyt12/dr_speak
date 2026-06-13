import SwiftUI
import SwiftData

/// Appointments that haven't been completed yet — i.e. they don't have a
/// visit summary, so the patient is still preparing for or attending them.
struct UpcomingAppointmentsView: View {
    @Query(sort: \Appointment.date, order: .reverse) private var allAppointments: [Appointment]

    private var appointments: [Appointment] {
        allAppointments.filter { $0.visit_summary.isEmpty }
    }

    var body: some View {
        List {
            ForEach(Array(appointments.enumerated()), id: \.element.id) { index, appointment in
                NavigationLink(destination: AppointmentDetailView(appointment: appointment)) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color(red: 0.11, green: 0.49, blue: 0.78))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(appointment.appointment_title.isEmpty ? "Appointment \(appointments.count - index)" : appointment.appointment_title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.2))
                            Text("Created: \(appointment.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Upcoming Appointments")
        .navigationBarTitleDisplayMode(.inline)
    }
}
