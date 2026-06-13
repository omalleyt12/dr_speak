import Foundation

enum GrokError: Error {
    case invalidResponse
    case apiError(String)
}

struct GrokService {
    private static let apiKey = GROK_API_KEY
    private static let endpoint = URL(string: "https://api.x.ai/v1/chat/completions")!
    private static let model = "grok-3"

    static func chat(messages: [ChatMessage], prompt: String) async throws -> String {
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": prompt]
        ]

        for message in messages {
            let role = message.isUser ? "user" : "assistant"
            apiMessages.append(["role": role, "content": message.text])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "max_tokens": 500,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GrokError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard http.statusCode == 200,
              let choices = json?["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            let errorMsg = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw GrokError.apiError(errorMsg)
        }

        return content
    }

    static func cleanTranscript(_ rawText: String) async throws -> String {
        let systemPrompt = """
        You are a medical transcription editor. Clean up the following raw speech-to-text transcript \
        from a doctor's visit. Fix punctuation, capitalization, and medical terminology. \
        Preserve all content — do not summarize or remove anything. Return only the cleaned transcript text, no commentary.
        """
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": rawText]
            ],
            "max_tokens": 2048
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GrokError.invalidResponse }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard http.statusCode == 200,
              let choices = json?["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            let errorMsg = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw GrokError.apiError(errorMsg)
        }
        return content
    }

    static func transcribe(audioURL: URL) async throws -> String {
        let transcribeEndpoint = URL(string: "https://api.x.ai/v1/audio/transcriptions")!
        let boundary = UUID().uuidString
        var request = URLRequest(url: transcribeEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-large-v3\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GrokError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard http.statusCode == 200,
              let text = json?["text"] as? String else {
            let errorMsg = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw GrokError.apiError(errorMsg)
        }

        return text
    }
}
