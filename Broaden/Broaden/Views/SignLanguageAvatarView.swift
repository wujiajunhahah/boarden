import SwiftUI
import WebKit

/// 手语数字人在线页面 URL（需要部署到 broaden.cc）
private let signLanguageAvatarBaseURL = "https://broaden.cc/sign_language_avatar.html"

/// 手语数字人视图 - 使用 WKWebView 加载手语翻译服务
struct SignLanguageAvatarView: View {
    let textToTranslate: String
    
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            SignLanguageWebView(
                textToTranslate: textToTranslate,
                isLoading: $isLoading,
                hasError: $hasError,
                errorMessage: $errorMessage
            )
            
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("加载手语数字人...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial)
            }
            
            if hasError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text("手语服务加载失败")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial)
            }
        }
    }
}

/// WKWebView 的 SwiftUI 包装器
struct SignLanguageWebView: UIViewRepresentable {
    let textToTranslate: String
    @Binding var isLoading: Bool
    @Binding var hasError: Bool
    @Binding var errorMessage: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        
        // 注册消息处理器
        contentController.add(context.coordinator, name: "loadComplete")
        contentController.add(context.coordinator, name: "loadError")
        contentController.add(context.coordinator, name: "debugLog")
        
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        // 存储 webView 引用以便后续使用
        context.coordinator.webView = webView
        
        // 构建在线页面 URL（部署在 broaden.cc）
        // URL 参数: text=翻译文本, secret=APPSecret
        if let appSecret = Secrets.shared.signLanguageAppSecret,
           let encodedText = textToTranslate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let encodedSecret = appSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "\(signLanguageAvatarBaseURL)?text=\(encodedText)&secret=\(encodedSecret)") {
            print("[SignLanguage] 加载在线页面: \(signLanguageAvatarBaseURL)")
            webView.load(URLRequest(url: url))
        } else {
            print("[SignLanguage] 错误: 无法构建 URL")
            DispatchQueue.main.async {
                self.hasError = true
                self.errorMessage = "配置错误"
            }
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // 当文本变化时，调用 JS 函数更新翻译
        let escapedText = textToTranslate
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let script = "if (typeof translateText === 'function') { translateText('\(escapedText)'); }"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 清理消息处理器，防止内存泄漏
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "loadComplete")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "loadError")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "debugLog")
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: SignLanguageWebView
        weak var webView: WKWebView?
        
        init(_ parent: SignLanguageWebView) {
            self.parent = parent
        }
        
        // MARK: - WKScriptMessageHandler
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            DispatchQueue.main.async {
                switch message.name {
                case "loadComplete":
                    print("[SignLanguage] 加载完成: \(message.body)")
                    self.parent.isLoading = false
                    self.parent.hasError = false
                    
                case "loadError":
                    let errorMsg = message.body as? String ?? "未知错误"
                    print("[SignLanguage] 加载错误: \(errorMsg)")
                    self.parent.isLoading = false
                    self.parent.hasError = true
                    self.parent.errorMessage = errorMsg
                    
                case "debugLog":
                    print("[SignLanguage-JS] \(message.body)")
                    
                default:
                    break
                }
            }
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[SignLanguage] WebView 页面加载完成")
            // 页面加载完成，但 SDK 可能还在初始化
            // 超时保护：如果 10 秒后还没收到 loadComplete，自动隐藏 loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if self.parent.isLoading {
                    print("[SignLanguage] 加载超时，强制完成")
                    self.parent.isLoading = false
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[SignLanguage] 导航失败: \(error.localizedDescription)")
            parent.isLoading = false
            parent.hasError = true
            parent.errorMessage = error.localizedDescription
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[SignLanguage] 预导航失败: \(error.localizedDescription)")
            parent.isLoading = false
            parent.hasError = true
            parent.errorMessage = error.localizedDescription
        }
        
        // 允许所有 HTTPS 请求
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

#Preview {
    SignLanguageAvatarView(textToTranslate: "你好，欢迎参观博物馆")
        .frame(height: 300)
}
