import Foundation

@MainActor
final class AskViewModel: ObservableObject {
    @Published var messages: [ConversationMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let askService: AskServicing
    private let cache = AnswerCache()

    init(askService: AskServicing? = nil) {
        if let askService {
            self.askService = askService
        } else {
            self.askService = DeepSeekAskService()
        }
    }

    func ask(exhibitId: String, question: String, contextText: String? = nil) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = ConversationMessage(isUser: true, text: trimmed, response: nil)
        messages.append(userMessage)
        isLoading = true
        errorMessage = nil
        Haptics.lightImpact()

        Task {
            let request = AskRequest(exhibitId: exhibitId, question: trimmed, contextText: contextText)
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
                handleError(error)
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
        errorMessage = "未获取到回答，请稍后重试"
    }

    private func handleError(_ error: Error) {
        isLoading = false
        if let serviceError = error as? AskServiceError {
            errorMessage = serviceError.localizedDescription
        } else {
            errorMessage = "请求失败，请稍后重试"
        }
    }

    func quickAsk(exhibitId: String, question: String, contextText: String? = nil) {
        ask(exhibitId: exhibitId, question: question, contextText: contextText)
    }
}
