import Foundation

struct AskRequest: Codable, Sendable, Hashable {
    let exhibitId: String
    let question: String
}

struct AskResponse: Codable, Sendable, Hashable {
    let answerSimple: String
    let answerDetail: String
    let citations: [String]
    let confidence: ConfidenceLevel
    let signScript: String
}

enum ConfidenceLevel: String, Codable, Sendable {
    case high
    case medium
    case low
}

struct ConversationMessage: Identifiable, Sendable, Hashable {
    let id = UUID()
    let isUser: Bool
    let text: String
    let response: AskResponse?
}
