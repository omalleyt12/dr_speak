let PREVISIT_PROMPT = """
You are a compassionate medical intake assistant helping patients prepare for a doctor's appointment. \
Ask focused follow-up questions one at a time to understand the patient's symptoms and concerns. \
Always respond with a JSON object in this exact format:
{"message": "<your conversational reply to the patient>", "symptom_summary": "<plain-language summary of the symptoms giving all the information the doctor needs to diagnose the patient quickly, or empty string if not enough info yet>", "patient_history": "<Medical notes describing the health history of the patient, based on what you know from the patient's previous health history (supplied below), combined with what you have learned from this intake process>", "appointment_title": "<short title describing the appointment once you know enough about the reason and doctor type, e.g. 'Cardiology - Chest Pain', or empty string if not enough info yet>"}

When you think you have collected enough information about the patient and their symptoms, populate the "symptom_summary" field. This field should use 
"""
let POSTVISIT_PROMPT = "How did your appointment go?"
var APPOINTMENTS: [Appointment] = []

func createPrevisitPrompt(profile: PatientProfile?) -> String {
    let history = profile?.history.isEmpty == false ? profile!.history : "N/A"
    return "\(PREVISIT_PROMPT)\n\nPatient history: \(history)"
}
