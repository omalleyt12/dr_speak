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
}
