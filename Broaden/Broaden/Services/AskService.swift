import Foundation

protocol AskServicing: Sendable {
    func ask(request: AskRequest) async throws -> AskResponse?
}

enum AskServiceError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case requestFailed(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 DeepSeek API Key"
        case .requestFailed(let statusCode):
            return "联网失败（HTTP \(statusCode)）"
        case .invalidResponse:
            return "返回格式无效，请稍后重试"
        }
    }
}

struct DeepSeekAskService: AskServicing {
    private let service: DeepSeekServicing = DeepSeekService()

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
            throw AskServiceError.invalidResponse
        }
        guard let data = extractJSONData(from: response.text),
              let parsed = try? JSONDecoder().decode(AskResponseDTO.self, from: data) else {
            throw AskServiceError.invalidResponse
        }

        return AskResponse(
            answerSimple: parsed.answer_simple,
            answerDetail: parsed.answer_detail,
            citations: parsed.citations,
            confidence: parsed.confidence,
            signScript: parsed.sign_script
        )
    }

    private struct AskResponseDTO: Codable, Sendable {
        let answer_simple: String
        let answer_detail: String
        let sign_script: String
        let citations: [String]
        let confidence: ConfidenceLevel
    }

    private func extractJSONData(from text: String) -> Data? {
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        guard let start = text.firstIndex(of: "{") else { return nil }
        guard let end = text.lastIndex(of: "}") else { return nil }
        let substring = String(text[start...end])
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
