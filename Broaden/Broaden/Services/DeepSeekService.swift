import Foundation

struct DeepSeekResponse: Sendable, Hashable {
    let text: String
}

protocol DeepSeekServicing: Sendable {
    func generate(system: String, user: String) async throws -> DeepSeekResponse?
}

// MARK: - 通义千问服务（实现 DeepSeekServicing 接口以兼容现有代码）

struct QwenService: DeepSeekServicing {
    func generate(system: String, user: String) async throws -> DeepSeekResponse? {
        guard let apiKey = Secrets.shared.qwenApiKey, !apiKey.isEmpty else {
            print("[Qwen] 错误: 未配置 API Key")
            return nil
        }

        let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
        let model = "qwen-turbo"
        
        print("[Qwen] 请求: \(endpoint), model: \(model)")

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
        guard let http = response as? HTTPURLResponse else {
            print("[Qwen] 错误: 无法获取 HTTP 响应")
            return nil
        }
        
        print("[Qwen] HTTP 状态码: \(http.statusCode)")
        
        guard (200...299).contains(http.statusCode) else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("[Qwen] 错误响应: \(errorText.prefix(500))")
            }
            return nil
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            print("[Qwen] 警告: 返回内容为空")
        }
        
        return trimmed.isEmpty ? nil : DeepSeekResponse(text: trimmed)
    }
}

// MARK: - DeepSeek 服务（保留但不使用）

struct DeepSeekService: DeepSeekServicing {
    func generate(system: String, user: String) async throws -> DeepSeekResponse? {
        guard let apiKey = Secrets.shared.deepseekApiKey else {
            print("[DeepSeek] 错误: 未配置 API Key")
            return nil
        }

        let endpoint = Secrets.shared.deepseekBaseURL.appendingPathComponent("chat/completions")
        let model = Secrets.shared.deepseekChatModel
        
        print("[DeepSeek] 请求: \(endpoint), model: \(model)")

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
        guard let http = response as? HTTPURLResponse else {
            print("[DeepSeek] 错误: 无法获取 HTTP 响应")
            return nil
        }
        
        print("[DeepSeek] HTTP 状态码: \(http.statusCode)")
        
        guard (200...299).contains(http.statusCode) else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("[DeepSeek] 错误响应: \(errorText.prefix(500))")
            }
            return nil
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            print("[DeepSeek] 警告: 返回内容为空")
        }
        
        return trimmed.isEmpty ? nil : DeepSeekResponse(text: trimmed)
    }
}
