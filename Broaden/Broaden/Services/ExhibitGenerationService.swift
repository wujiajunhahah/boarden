import Foundation

protocol ExhibitGenerating: Sendable {
    func generate(from ocrText: String) async throws -> Exhibit?
}

enum ExhibitGenerationError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case invalidResponse
    case ocrEmpty

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置智谱 API Key"
        case .invalidResponse:
            return "返回格式无效，请稍后重试"
        case .ocrEmpty:
            return "未能识别到文字，请重新拍摄"
        }
    }
}

struct ExhibitGenerationService: ExhibitGenerating {
    private let service: ZhipuChatServicing = ZhipuChatService()

    func generate(from ocrText: String) async throws -> Exhibit? {
        let cleaned = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ExhibitGenerationError.ocrEmpty }

        guard Secrets.shared.zhipuApiKey != nil else {
            throw ExhibitGenerationError.missingAPIKey
        }

        let system = """
        你是博物馆讲解员与策展助理。仅基于输入文字生成展品条目，不要引入外部知识。
        只输出严格 JSON，不要解释。
        JSON 字段：id, title, shortIntro, easyText, detailText, glossary[{term,def}], media{signVideoFilename,captionsVttOrSrtFilename}, references[{refId,snippet}]
        id 用 EXH- 开头，title 必须来自文字中可识别的展品名称。
        若信息不足，用中性表述。media 固定：sign_demo.mp4 与 captions_demo.srt。
        """

        let user = "识别到的展牌文字：\n\(cleaned)\n请生成展品 JSON。"

        guard let response = try await service.generate(system: system, user: user) else {
            throw ExhibitGenerationError.invalidResponse
        }

        guard let jsonData = extractJSONData(from: response),
              let exhibit = try? JSONDecoder().decode(Exhibit.self, from: jsonData) else {
            print("[ExhibitGeneration] JSON 解析失败，响应: \(response)")
            throw ExhibitGenerationError.invalidResponse
        }

        return exhibit
    }

    private func extractJSONData(from text: String) -> Data? {
        // 先尝试直接解析
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        // 尝试提取 JSON 对象
        guard let start = text.firstIndex(of: "{") else { return nil }
        guard let end = text.lastIndex(of: "}") else { return nil }
        let substring = String(text[start...end])
        return substring.data(using: .utf8)
    }
}
