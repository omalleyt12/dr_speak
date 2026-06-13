import SwiftData
import Foundation

@Model
class PatientProfile {
    var history: String

    init(history: String = "") {
        self.history = history
    }
}
