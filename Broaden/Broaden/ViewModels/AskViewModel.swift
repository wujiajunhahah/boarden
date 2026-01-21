import Foundation

@MainActor
final class AskViewModel: ObservableObject {
    @Published var messages: [ConversationMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let askService: AskServicing
    private let cache = AnswerCache()

    init(askService: AskServicing = MockAskService()) {
        self.askService = askService
    }

    func ask(exhibitId: String, question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = ConversationMessage(isUser: true, text: trimmed, response: nil)
        messages.append(userMessage)
        isLoading = true
        errorMessage = nil
        Haptics.lightImpact()

        Task {
            let request = AskRequest(exhibitId: exhibitId, question: trimmed)
            if let cached = await cache.load(for: request) {
                appendResponse(cached)
                return
            }

            do {
                let response = try await askService.ask(request: request)
                if let response {
                    await cache.save(response, for: request)
                    appendResponse(response)
                } else {
                    handleNoResult()
                }
            } catch {
                handleNoResult()
            }
        }
    }

    private func appendResponse(_ response: AskResponse) {
        let message = ConversationMessage(isUser: false, text: response.answerSimple, response: response)
        messages.append(message)
        isLoading = false
    }

    private func handleNoResult() {
        isLoading = false
        errorMessage = "馆方资料未包含该细节"
    }

    func quickAsk(exhibitId: String, question: String) {
        ask(exhibitId: exhibitId, question: question)
    }
}
