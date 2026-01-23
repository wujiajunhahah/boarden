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

/// 智谱展品解说服务（使用智谱 AI）
struct ZhipuNarrationService: ExhibitNarrationServicing {
    private let service: ZhipuChatServicing = ZhipuChatService()

    func generate(title: String) async throws -> ExhibitNarration? {
        let system = "你是博物馆讲解员，输出中文、克制、清晰。"
        let user = "请为展品《\(title)》生成：1) 易读版 3-5 句 2) 详细版 6-10 句。用换行分隔，格式：易读版：... 详细版：..."

        guard let response = try await service.generate(system: system, user: user) else {
            return nil
        }

        let easy = extract(response, keyword: "易读版") ?? ""
        let detail = extract(response, keyword: "详细版") ?? ""

        if easy.isEmpty && detail.isEmpty {
            return nil
        }

        return ExhibitNarration(easyText: easy.isEmpty ? response : easy, detailText: detail.isEmpty ? response : detail)
    }

    private func extract(_ text: String, keyword: String) -> String? {
        guard let range = text.range(of: keyword) else { return nil }
        var after = String(text[range.upperBound...])
        
        // 移除开头的冒号和空白
        after = after.trimmingCharacters(in: CharacterSet(charactersIn: "：:").union(.whitespaces))
        
        // 如果有"详细版"关键字，截取到它之前
        if keyword == "易读版", let detailRange = after.range(of: "详细版") {
            after = String(after[..<detailRange.lowerBound])
        }
        
        // 清理并返回
        let result = after.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
