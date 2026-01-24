import Foundation

protocol AskServicing: Sendable {
    func ask(request: AskRequest) async throws -> AskResponse?
}

enum AskServiceError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case requestFailed(statusCode: Int)
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置智谱 API Key"
        case .requestFailed(let statusCode):
            return "联网失败（HTTP \(statusCode)）"
        case .invalidResponse:
            return "返回格式无效，请稍后重试"
        case .apiError(let msg):
            return msg
        }
    }
}

/// 使用智谱 AI 的问答服务
struct ZhipuAskService: AskServicing {
    private let service: ZhipuChatServicing = ZhipuChatService()

    func ask(request: AskRequest) async throws -> AskResponse? {
        let trimmed = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard Secrets.shared.isValidZhipuKey else {
            throw AskServiceError.missingAPIKey
        }

        let system = """
        你是博物馆无障碍导览助手。结合提供的展品上下文回答用户问题。
        必须输出严格 JSON 格式，不要有任何其他文字：
        {
          "answer_simple": "简短回答（口语化、短句、避免复杂术语和从句，适合直接转为手语动作）",
          "answer_detail": "详细回答（比如，包含背景知识、历史典故、工艺细节等）",
          "sign_script": "手语翻译脚本（与 answer_simple 内容一致，但每句话独立成行，方便逐句转为手语）",
          "citations": ["引用来源1", "引用来源2"],
          "confidence": "high/medium/low"
        }
        注意：answer_simple 需要特别简洁易懂，使用日常用语，每句不超过15字。
        """
        let user = """
        展品ID：\(request.exhibitId)
        上下文（仅供参考，不要超出）：\(request.contextText ?? "无")
        用户问题：\(trimmed)
        请生成 JSON。
        """

        guard let response = try await service.generate(system: system, user: user) else {
            print("[ZhipuAsk] API 返回空值")
            throw AskServiceError.invalidResponse
        }

        print("[ZhipuAsk] API 响应: \(response.prefix(500))")

        // 尝试提取 JSON
        guard let data = extractJSONData(from: response) else {
            print("[ZhipuAsk] 无法提取 JSON")
            throw AskServiceError.invalidResponse
        }

        print("[ZhipuAsk] 提取的 JSON: \(String(data: data, encoding: .utf8) ?? "nil")")

        guard let parsed = try? JSONDecoder().decode(AskResponseDTO.self, from: data) else {
            print("[ZhipuAsk] JSON 解析失败")
            // 尝试直接使用原始文本
            return fallbackResponse(from: response)
        }

        return AskResponse(
            answerSimple: parsed.answer_simple,
            answerDetail: parsed.answer_detail,
            citations: parsed.citations,
            confidence: parsed.confidence,
            signScript: parsed.sign_script ?? ""  // 使用默认值
        )
    }

    /// 当 JSON 解析失败时的回退方案
    private func fallbackResponse(from text: String) -> AskResponse? {
        // 尝试从原始文本中提取可读内容（去除 JSON 结构）
        var cleanText = text

        // 移除可能的 JSON/markdown 标记
        if let range = text.range(of: "```json") {
            cleanText = String(text[range.upperBound...])
        }
        if let range = text.range(of: "```") {
            cleanText = String(text[..<range.lowerBound])
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 如果是 JSON 格式，尝试提取 answer_simple 或 answer_detail
        if let data = cleanText.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let simple = json["answer_simple"] as? String ?? json["answerSimple"] as? String
            let detail = json["answer_detail"] as? String ?? json["answerDetail"] as? String

            return AskResponse(
                answerSimple: simple ?? String(text.prefix(100)),
                answerDetail: detail ?? text,
                citations: [],
                confidence: .medium,
                signScript: ""  // 解析失败时不生成手语脚本
            )
        }

        // 非 JSON 格式，直接使用文本
        return AskResponse(
            answerSimple: String(text.prefix(150)),
            answerDetail: text,
            citations: [],
            confidence: .low,
            signScript: ""  // 解析失败时不生成手语脚本
        )
    }

    private struct AskResponseDTO: Codable, Sendable {
        let answer_simple: String
        let answer_detail: String
        let sign_script: String?  // 改为可选，因为 API 可能不返回
        let citations: [String]
        let confidence: ConfidenceLevel
    }

    private func extractJSONData(from text: String) -> Data? {
        // 先尝试直接解析
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

        // 尝试提取 JSON 对象（处理 ```json 包裹的情况）
        var processedText = text

        // 移除 markdown 代码块标记
        if let jsonRange = processedText.range(of: "```json", options: .caseInsensitive) {
            processedText = String(processedText[jsonRange.upperBound...])
        }
        if processedText.hasPrefix("```") {
            processedText = String(processedText.dropFirst(3))
        }

        // 移除结尾的 ```
        if let endRange = processedText.range(of: "```", options: .caseInsensitive) {
            processedText = String(processedText[..<endRange.lowerBound])
        }
        processedText = processedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 提取 JSON 对象
        guard let start = processedText.firstIndex(of: "{") else { return nil }
        guard let end = processedText.lastIndex(of: "}") else { return nil }
        let substring = String(processedText[start...end])
        return substring.data(using: .utf8)
    }
}

/// 已废弃的 DeepSeek 服务（保留用于兼容性）
struct DeepSeekAskService: AskServicing {
    func ask(request: AskRequest) async throws -> AskResponse? {
        throw AskServiceError.missingAPIKey
    }
}

actor MockAskService: AskServicing {
    func ask(request: AskRequest) async throws -> AskResponse? {
        let trimmed = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        throw AskServiceError.missingAPIKey
    }
}
