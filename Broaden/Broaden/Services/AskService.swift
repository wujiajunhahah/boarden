import Foundation

protocol AskServicing: Sendable {
    func ask(request: AskRequest) async throws -> AskResponse?
}

enum AskServiceError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case requestFailed(statusCode: Int)
    case invalidResponse
    case noResponse
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 API Key"
        case .requestFailed(let statusCode):
            return "联网失败（HTTP \(statusCode)）"
        case .invalidResponse:
            return "返回格式无效，请稍后重试"
        case .noResponse:
            return "API 无返回，请检查网络"
        case .parseError(let detail):
            return "解析失败: \(detail)"
        }
    }
}

// MARK: - 通义千问 AskService

struct QwenAskService: AskServicing {
    func ask(request: AskRequest) async throws -> AskResponse? {
        let trimmed = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let apiKey = Secrets.shared.qwenApiKey, !apiKey.isEmpty else {
            print("[Qwen] 错误: 未配置 API Key")
            throw AskServiceError.missingAPIKey
        }

        let system = """
        你是博物馆无障碍导览助手。只能根据提供的展品上下文回答。
        若上下文不足，请明确说明"馆方资料未包含该细节"，不要编造。
        输出严格 JSON，不要解释。
        JSON 字段：answer_simple, answer_detail, sign_script, citations, confidence
        confidence 只能是 high/medium/low
        """
        let user = """
        展品ID：\(request.exhibitId)
        上下文（仅供参考，不要超出）：\(request.contextText ?? "无")
        用户问题：\(trimmed)
        请生成 JSON。
        """

        // 通义千问 API 端点
        let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
        
        let payload: [String: Any] = [
            "model": "qwen-turbo",
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

        print("[Qwen] 发送请求到: \(endpoint)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("[Qwen] 错误: 无法获取 HTTP 响应")
            throw AskServiceError.noResponse
        }
        
        print("[Qwen] HTTP 状态码: \(http.statusCode)")
        
        guard (200...299).contains(http.statusCode) else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("[Qwen] 错误响应: \(errorText.prefix(500))")
            }
            throw AskServiceError.requestFailed(statusCode: http.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        let responseText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("[Qwen] API 返回: \(responseText.prefix(500))")
        
        guard !responseText.isEmpty else {
            throw AskServiceError.noResponse
        }
        
        guard let jsonData = extractJSONData(from: responseText) else {
            print("[Qwen] 无法提取 JSON")
            throw AskServiceError.parseError("无法提取JSON")
        }
        
        let decoder = JSONDecoder()
        
        // 尝试解析
        if let parsed = try? decoder.decode(AskResponseDTO.self, from: jsonData) {
            return AskResponse(
                answerSimple: parsed.answer_simple,
                answerDetail: parsed.answer_detail,
                citations: parsed.citations ?? [],
                confidence: parsed.confidence ?? .medium,
                signScript: parsed.sign_script ?? ""
            )
        }
        
        // 备用解析
        if let parsed = try? decoder.decode(AskResponseDTOFallback.self, from: jsonData) {
            return AskResponse(
                answerSimple: parsed.answer_simple ?? parsed.answerSimple ?? "无法获取回答",
                answerDetail: parsed.answer_detail ?? parsed.answerDetail ?? "",
                citations: parsed.citations ?? [],
                confidence: parsed.confidence ?? .medium,
                signScript: parsed.sign_script ?? parsed.signScript ?? ""
            )
        }
        
        throw AskServiceError.parseError("JSON解码失败")
    }
    
    private func extractJSONData(from text: String) -> Data? {
        var cleanText = text
        if cleanText.contains("```json") {
            cleanText = cleanText.replacingOccurrences(of: "```json", with: "")
        }
        if cleanText.contains("```") {
            cleanText = cleanText.replacingOccurrences(of: "```", with: "")
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let data = cleanText.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        
        guard let start = cleanText.firstIndex(of: "{") else { return nil }
        guard let end = cleanText.lastIndex(of: "}") else { return nil }
        let substring = String(cleanText[start...end])
        return substring.data(using: .utf8)
    }
    
    private struct AskResponseDTO: Codable, Sendable {
        let answer_simple: String
        let answer_detail: String
        let sign_script: String?
        let citations: [String]?
        let confidence: ConfidenceLevel?
    }
    
    private struct AskResponseDTOFallback: Codable, Sendable {
        let answer_simple: String?
        let answer_detail: String?
        let sign_script: String?
        let citations: [String]?
        let confidence: ConfidenceLevel?
        let answerSimple: String?
        let answerDetail: String?
        let signScript: String?
    }
}

struct DeepSeekAskService: AskServicing {
    private let service: DeepSeekServicing = QwenService()

    func ask(request: AskRequest) async throws -> AskResponse? {
        let trimmed = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if Secrets.shared.deepseekApiKey == nil {
            throw AskServiceError.missingAPIKey
        }

        let system = """
        你是博物馆无障碍导览助手。只能根据提供的展品上下文回答。
        若上下文不足，请明确说明“馆方资料未包含该细节”，不要编造。
        输出严格 JSON，不要解释。
        JSON 字段：answer_simple, answer_detail, sign_script, citations, confidence
        confidence 只能是 high/medium/low
        """
        let user = """
        展品ID：\(request.exhibitId)
        上下文（仅供参考，不要超出）：\(request.contextText ?? "无")
        用户问题：\(trimmed)
        请生成 JSON。
        """

        guard let response = try await service.generate(system: system, user: user) else {
            print("[AskService] API 返回 nil")
            throw AskServiceError.noResponse
        }
        
        print("[AskService] API 返回: \(response.text.prefix(800))")
        
        guard let data = extractJSONData(from: response.text) else {
            print("[AskService] 无法提取 JSON，原始文本: \(response.text.prefix(200))")
            throw AskServiceError.parseError("无法提取JSON")
        }
        
        // 打印提取的 JSON
        if let jsonString = String(data: data, encoding: .utf8) {
            print("[AskService] 提取的 JSON: \(jsonString.prefix(500))")
        }
        
        // 尝试解析，使用更宽松的解码器
        let decoder = JSONDecoder()
        
        // 首先尝试标准解析
        do {
            let parsed = try decoder.decode(AskResponseDTO.self, from: data)
            return AskResponse(
                answerSimple: parsed.answer_simple,
                answerDetail: parsed.answer_detail,
                citations: parsed.citations ?? [],
                confidence: parsed.confidence ?? .medium,
                signScript: parsed.sign_script ?? ""
            )
        } catch {
            print("[AskService] 标准解析失败: \(error)")
        }
        
        // 尝试更宽松的解析
        do {
            let parsed = try decoder.decode(AskResponseDTOFallback.self, from: data)
            return AskResponse(
                answerSimple: parsed.answer_simple ?? parsed.answerSimple ?? "无法获取回答",
                answerDetail: parsed.answer_detail ?? parsed.answerDetail ?? "",
                citations: parsed.citations ?? [],
                confidence: parsed.confidence ?? .medium,
                signScript: parsed.sign_script ?? parsed.signScript ?? ""
            )
        } catch {
            print("[AskService] 备用解析失败: \(error)")
        }
        
        throw AskServiceError.parseError("JSON解码失败")
    }

    private struct AskResponseDTO: Codable, Sendable {
        let answer_simple: String
        let answer_detail: String
        let sign_script: String?
        let citations: [String]?
        let confidence: ConfidenceLevel?
    }
    
    // 备用解析结构，支持驼峰命名
    private struct AskResponseDTOFallback: Codable, Sendable {
        let answer_simple: String?
        let answer_detail: String?
        let sign_script: String?
        let citations: [String]?
        let confidence: ConfidenceLevel?
        // 驼峰版本
        let answerSimple: String?
        let answerDetail: String?
        let signScript: String?
    }

    private func extractJSONData(from text: String) -> Data? {
        // 移除 markdown 代码块标记
        var cleanText = text
        if cleanText.contains("```json") {
            cleanText = cleanText.replacingOccurrences(of: "```json", with: "")
        }
        if cleanText.contains("```") {
            cleanText = cleanText.replacingOccurrences(of: "```", with: "")
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 尝试直接解析
        if let data = cleanText.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        
        // 提取 JSON 对象
        guard let start = cleanText.firstIndex(of: "{") else { return nil }
        guard let end = cleanText.lastIndex(of: "}") else { return nil }
        let substring = String(cleanText[start...end])
        return substring.data(using: .utf8)
    }
}

actor MockAskService: AskServicing {
    func ask(request: AskRequest) async throws -> AskResponse? {
        let trimmed = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        throw AskServiceError.missingAPIKey
    }
}
