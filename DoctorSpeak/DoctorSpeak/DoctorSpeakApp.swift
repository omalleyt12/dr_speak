import SwiftUI
import SwiftData

@main
struct DoctorSpeakApp: App {
    let container: ModelContainer = {
        do {
            let c = try ModelContainer(for: Appointment.self)
            let context = ModelContext(c)
            APPOINTMENTS = (try? context.fetch(FetchDescriptor<Appointment>())) ?? []
            return c
        } catch {
            // Schema changed — wipe the old store and start fresh
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: url)
            let c = try! ModelContainer(for: Appointment.self)
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
