import Foundation

struct Secrets {
    static let shared = Secrets()

    // 智谱 AI 配置
    let zhipuApiKey: String?
    let zhipuBaseURL: URL
    let zhipuOCRModel: String
    let zhipuChatModel: String

    /// 手语数字人服务 APPSecret
    let signLanguageAppSecret: String?

    private init() {
        let defaults = (
            zhipuBaseURL: URL(string: "https://open.bigmodel.cn/api/paas/v4")!,
            zhipuOCRModel: "glm-4v-flash",
            zhipuChatModel: "glm-4-flash"
        )

        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            zhipuApiKey = plist["ZHIPU_API_KEY"] as? String
            signLanguageAppSecret = plist["SIGN_LANGUAGE_APP_SECRET"] as? String

            if let base = plist["ZHIPU_BASE_URL"] as? String, let url = URL(string: base) {
                zhipuBaseURL = url
            } else {
                zhipuBaseURL = defaults.zhipuBaseURL
            }

            zhipuOCRModel = plist["ZHIPU_OCR_MODEL"] as? String ?? defaults.zhipuOCRModel
            zhipuChatModel = plist["ZHIPU_CHAT_MODEL"] as? String ?? defaults.zhipuChatModel
        } else {
            zhipuApiKey = nil
            signLanguageAppSecret = nil
            zhipuBaseURL = defaults.zhipuBaseURL
            zhipuOCRModel = defaults.zhipuOCRModel
            zhipuChatModel = defaults.zhipuChatModel
        }
    }

    /// 验证智谱 API Key 是否有效（非占位符）
    var isValidZhipuKey: Bool {
        guard let key = zhipuApiKey else { return false }
        return !key.isEmpty && !key.hasPrefix("YOUR_") && key.contains(".")
    }
}
