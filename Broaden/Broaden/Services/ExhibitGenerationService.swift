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
        你是博物馆讲解员与策展助理。请准确识别拍摄的展品是什么；若有拍摄展牌，则借助拍摄的展牌文字，生成展品条目。
        只输出严格 JSON，不要解释。如果识别到的展品名称与展牌文字不一致，请使用展牌文字中的展品名称。
        JSON 字段：id, title, shortIntro, easyText, detailText, glossary[{term,def}], media{signVideoFilename,captionsVttOrSrtFilename}, references[{refId,snippet}]
        
        重要要求：
        - id 用 EXH- 开头加4位数字
        - title 必须来自文字中可识别的展品名称
        - shortIntro 必须是1-2句话的简短介绍
        - easyText 必须是通俗易懂的描述，至少50字，适合普通观众阅读
        - detailText 必须是详细的专业描述，至少100字，包含历史背景、工艺特点等
        - glossary 至少包含1-3个专业术语及其解释
        - 若信息不足，请根据展品类型合理推测并用中性表述
        - media 固定：sign_demo.mp4 与 captions_demo.srt
        - 所有文本字段不能为空，不能只有标点符号
        """

        let user = "识别到的展牌文字：\n\(cleaned)\n请生成展品 JSON。"

        guard let response = try await service.generate(system: system, user: user) else {
            throw ExhibitGenerationError.invalidResponse
        }

        guard let jsonData = extractJSONData(from: response),
              var exhibit = try? JSONDecoder().decode(Exhibit.self, from: jsonData) else {
            print("[ExhibitGeneration] JSON 解析失败，响应: \(response)")
            throw ExhibitGenerationError.invalidResponse
        }

        // 使用 UUID 生成唯一 ID，避免 LLM 生成的 ID 重复导致覆盖
        exhibit = Exhibit(
            id: "EXH-\(UUID().uuidString.prefix(8))",
            title: exhibit.title,
            shortIntro: exhibit.shortIntro,
            easyText: exhibit.easyText,
            detailText: exhibit.detailText,
            glossary: exhibit.glossary,
            media: exhibit.media,
            references: exhibit.references
        )

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
