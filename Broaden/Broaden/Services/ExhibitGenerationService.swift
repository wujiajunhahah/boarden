import Foundation

protocol ExhibitGenerating: Sendable {
    func generate(from ocrText: String) async throws -> Exhibit?
}

enum ExhibitGenerationError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 DeepSeek API Key"
        case .invalidResponse:
            return "返回格式无效，请稍后重试"
        }
    }
}

struct ExhibitGenerationService: ExhibitGenerating {
    private let service: DeepSeekServicing = DeepSeekService()

    func generate(from ocrText: String) async throws -> Exhibit? {
        let cleaned = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if Secrets.shared.deepseekApiKey == nil {
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

        if let response = try await service.generate(system: system, user: user),
           let jsonData = extractJSONData(from: response.text),
           let exhibit = try? JSONDecoder().decode(Exhibit.self, from: jsonData) {
            return exhibit
        }

        throw ExhibitGenerationError.invalidResponse
    }

    private func extractJSONData(from text: String) -> Data? {
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        // Try to extract JSON object substring
        guard let start = text.firstIndex(of: "{") else { return nil }
        guard let end = text.lastIndex(of: "}") else { return nil }
        let substring = String(text[start...end])
        return substring.data(using: .utf8)
    }

    private func fallbackExhibit(from text: String) -> Exhibit {
        let title = extractTitle(from: text)
        let shortIntro = extractShortIntro(from: text)
        let easy = extractEasyText(from: text)
        let detail = text

        return Exhibit(
            id: "EXH-LLM-\(UUID().uuidString.prefix(8))",
            title: title,
            shortIntro: shortIntro,
            easyText: easy,
            detailText: detail,
            glossary: [],
            media: ExhibitMedia(signVideoFilename: "sign_demo.mp4", captionsVttOrSrtFilename: "captions_demo.srt"),
            references: [ReferenceSnippet(refId: "REF-01", snippet: shortIntro)]
        )
    }

    private func extractTitle(from text: String) -> String {
        let lines = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        if let first = lines.first(where: { !$0.isEmpty }) {
            return String(first.prefix(16))
        }
        return String(text.prefix(12))
    }

    private func extractShortIntro(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = trimmed.firstIndex(where: { $0 == "。" || $0 == "；" || $0 == "." }) {
            return String(trimmed[..<idx])
        }
        return String(trimmed.prefix(40))
    }

    private func extractEasyText(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(120))
    }
}
