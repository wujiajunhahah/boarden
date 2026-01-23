import Foundation

struct ExhibitNarration: Sendable, Hashable {
    let easyText: String
    let detailText: String
}

protocol ExhibitNarrationServicing: Sendable {
    func generate(title: String) async throws -> ExhibitNarration?
}

/// 本地回退服务（无 API 调用）
struct ExhibitNarrationService: ExhibitNarrationServicing {
    func generate(title: String) async throws -> ExhibitNarration? {
        // 返回 nil，表示不生成解说
        return nil
    }
}

struct DeepSeekNarrationService: ExhibitNarrationServicing {
    private let service: DeepSeekServicing = QwenService()

    func generate(title: String) async throws -> ExhibitNarration? {
        let system = "你是博物馆讲解员，输出中文、克制、清晰。"
        let user = "请为展品《\(title)》生成：1) 易读版 3-5 句 2) 详细版 6-10 句。用换行分隔，格式：易读版：... 详细版：..."
        guard let response = try await service.generate(system: system, user: user) else { return nil }
        let text = response.text

        let easy = extract(text, keyword: "易读版") ?? ""
        let detail = extract(text, keyword: "详细版") ?? ""
        if easy.isEmpty && detail.isEmpty {
            return nil
        }
        return ExhibitNarration(easyText: easy.isEmpty ? text : easy, detailText: detail.isEmpty ? text : detail)
    }

    private func extract(_ text: String, keyword: String) -> String? {
        guard let range = text.range(of: keyword) else { return nil }
        let tail = text[range.upperBound...]
        let cleaned = tail.replacingOccurrences(of: "：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: "\n", maxSplits: 1).map { String($0) }
        return parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
