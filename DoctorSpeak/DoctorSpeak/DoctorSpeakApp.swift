import SwiftUI
import SwiftData

@main
struct DoctorSpeakApp: App {
    let container: ModelContainer = {
        do {
            let c = try ModelContainer(for: Appointment.self, PatientProfile.self)
            let context = ModelContext(c)
            APPOINTMENTS = (try? context.fetch(FetchDescriptor<Appointment>())) ?? []
            let profiles = (try? context.fetch(FetchDescriptor<PatientProfile>())) ?? []
            if profiles.isEmpty {
                context.insert(PatientProfile())
            }
            return c
        } catch {
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: url)
            let c = try! ModelContainer(for: Appointment.self, PatientProfile.self)
            let context = ModelContext(c)
            context.insert(PatientProfile())
            return c
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
