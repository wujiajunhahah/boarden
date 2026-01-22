import Foundation

struct DeepSeekResponse: Sendable, Hashable {
    let text: String
}

protocol DeepSeekServicing: Sendable {
    func generate(system: String, user: String) async throws -> DeepSeekResponse?
}

struct DeepSeekService: DeepSeekServicing {
    func generate(system: String, user: String) async throws -> DeepSeekResponse? {
        guard let apiKey = Secrets.shared.deepseekApiKey else {
            return nil
        }

        let endpoint = Secrets.shared.deepseekBaseURL.appendingPathComponent("chat/completions")
        let model = Secrets.shared.deepseekChatModel

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.4
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : DeepSeekResponse(text: trimmed)
    }
}
