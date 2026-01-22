import Foundation

struct Secrets {
    static let shared = Secrets()

    let qwenApiKey: String?
    let deepseekApiKey: String?
    let qwenBaseURL: URL
    let deepseekBaseURL: URL
    let qwenOCRModel: String
    let deepseekChatModel: String

    private init() {
        let defaults = (
            qwenBaseURL: URL(string: "https://dashscope.aliyuncs.com/api/v1")!,
            deepseekBaseURL: URL(string: "https://api.deepseek.com/v1")!,
            qwenOCRModel: "qwen-vl-ocr",
            deepseekChatModel: "deepseek-chat"
        )

        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            qwenApiKey = plist["QWEN_API_KEY"] as? String
            deepseekApiKey = plist["DEEPSEEK_API_KEY"] as? String

            if let base = plist["QWEN_BASE_URL"] as? String, let url = URL(string: base) {
                qwenBaseURL = url
            } else {
                qwenBaseURL = defaults.qwenBaseURL
            }

            if let base = plist["DEEPSEEK_BASE_URL"] as? String, let url = URL(string: base) {
                deepseekBaseURL = url
            } else {
                deepseekBaseURL = defaults.deepseekBaseURL
            }

            qwenOCRModel = plist["QWEN_OCR_MODEL"] as? String ?? defaults.qwenOCRModel
            deepseekChatModel = plist["DEEPSEEK_CHAT_MODEL"] as? String ?? defaults.deepseekChatModel
        } else {
            qwenApiKey = nil
            deepseekApiKey = nil
            qwenBaseURL = defaults.qwenBaseURL
            deepseekBaseURL = defaults.deepseekBaseURL
            qwenOCRModel = defaults.qwenOCRModel
            deepseekChatModel = defaults.deepseekChatModel
        }
    }
}
