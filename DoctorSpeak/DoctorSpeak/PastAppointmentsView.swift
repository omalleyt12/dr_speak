import SwiftUI
import SwiftData

struct PastAppointmentsView: View {
    @Query(sort: \Appointment.date, order: .reverse) private var appointments: [Appointment]

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
        .navigationTitle("Past Appointments")
        .navigationBarTitleDisplayMode(.inline)
    }
}
