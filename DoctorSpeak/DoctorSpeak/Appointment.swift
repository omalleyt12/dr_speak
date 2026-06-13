import SwiftData
import Foundation

struct PrevisitResponse: Codable {
    let message: String
    let symptomSummary: String
    let patientSummary: String
    let appointmentTitle: String

    enum CodingKeys: String, CodingKey {
        case message
        case symptomSummary = "symptom_summary"
        case patientSummary = "patient_summary"
        case appointmentTitle = "appointment_title"
    }
}

@Model
class Appointment {
    var id: UUID
    var date: Date
    var appointment_title: String
    var previsit_messages: [ChatMessage]
    var previsit_summary: String
    var visit: String
    var postvisit_messages: [ChatMessage]

    init(date: Date = .now) {
        self.id = UUID()
        self.date = date
        self.appointment_title = ""
        self.previsit_messages = []
        self.previsit_summary = ""
        self.visit = ""
        self.postvisit_messages = []
    }
}

@Model
class ChatMessage {
    var id: UUID
    var text: String
    var isUser: Bool
    var timestamp: Date

    init(text: String, isUser: Bool) {
        self.id = UUID()
        self.text = text
        self.isUser = isUser
        self.timestamp = .now
    }
}
