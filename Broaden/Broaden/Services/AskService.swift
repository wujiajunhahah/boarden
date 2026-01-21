import Foundation

protocol AskServicing: Sendable {
    func ask(request: AskRequest) async throws -> AskResponse?
}

actor MockAskService: AskServicing {
    private let templates: [String: AskResponse] = [
        "default": AskResponse(
            answerSimple: "这件展品的重要性主要体现在其工艺与时代背景。它帮助我们理解当时的社会审美与技术水平。",
            answerDetail: "根据馆内记录，这件展品在同类器物中保存完整，具有代表性。引用片段可能来自编目说明与修复档案。",
            citations: ["REF-01", "REF-03"],
            confidence: .medium,
            signScript: "展品的重要性：工艺精细，能代表当时的审美和技术。"
        )
    ]

    func ask(request: AskRequest) async throws -> AskResponse? {
        let trimmed = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        if trimmed.contains("修复") {
            return AskResponse(
                answerSimple: "馆方记录了多次维护，主要是加固与清洁。",
                answerDetail: "档案显示在上世纪末完成结构加固，并于近年进行表面清洁与环境监测调整。",
                citations: ["REF-02"],
                confidence: .high,
                signScript: "修复记录：曾加固和清洁，近年继续监测保护。"
            )
        }
        if trimmed.contains("术语") {
            return AskResponse(
                answerSimple: "术语通常描述工艺、材质或历史。",
                answerDetail: "可查看展牌中的术语卡片与馆内词汇表。",
                citations: ["REF-05"],
                confidence: .medium,
                signScript: "术语解释：多与工艺、材质和历史相关。"
            )
        }
        return templates["default"]
    }
}
