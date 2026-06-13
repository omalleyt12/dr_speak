import SwiftData
import Foundation

struct PrevisitResponse: Codable {
    let message: String
    let symptomSummary: String
    let patientHistory: String
    let appointmentTitle: String

    enum CodingKeys: String, CodingKey {
        case message
        case symptomSummary = "symptom_summary"
        case patientHistory = "patient_history"
        case appointmentTitle = "appointment_title"
    }
}

struct PostvisitResponse: Codable {
    let message: String
}

@Model
class Appointment {
    var id: UUID
    var date: Date
    var appointment_title: String
    var previsit_messages: [ChatMessage]
    var previsit_summary: String
    var visit_transcript: String
    var visit_summary: String
    var postvisit_messages: [ChatMessage]

    init(date: Date = .now) {
        self.id = UUID()
        self.date = date
        self.appointment_title = ""
        self.previsit_messages = []
        self.previsit_summary = ""
        self.visit_transcript = ""
        self.visit_summary = ""
        self.postvisit_messages = []
    }
}

@Model
class ChatMessage {
    var id: UUID
    var text: String
    var isUser: Bool
    var isSummary: Bool
    var timestamp: Date

    init(text: String, isUser: Bool, isSummary: Bool = false) {
        self.id = UUID()
        self.text = text
        self.isUser = isUser
        self.isSummary = isSummary
        self.timestamp = .now
    }
}
