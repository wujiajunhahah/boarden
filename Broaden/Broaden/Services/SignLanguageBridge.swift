import SwiftUI
import WebKit

/// 手语数字人在线页面 URL
private let signLanguageAvatarURL = "https://ios-avatar-web.vercel.app"

// MARK: - AvatarCoordinator

/// 手语数字人协调器 - 作为控制数字人的"遥控器"
/// 可以被多个视图共享，用于发送手语脚本、停止播放等操作
@MainActor
class AvatarCoordinator: ObservableObject {
    weak var webView: WKWebView?
    
    /// 当前正在翻译的文本
    @Published private(set) var currentText: String = ""
    
    /// WebView 是否已加载完成
    @Published var isLoaded: Bool = false
    
    /// 是否正在播放
    @Published private(set) var isPlaying: Bool = false
    
    /// 内部方法：设置播放状态（供 WebViewCoordinator 使用）
    func setPlaying(_ value: Bool) {
        isPlaying = value
    }
    
    /// 发送手语脚本到数字人
    /// - Parameter text: 要翻译的文本内容
    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        
        // 清理文本，防止换行符和引号导致 JS 语法错误
        // 注意：必须先转义反斜杠，否则后续添加的转义符会被再次转义
        let cleanText = text
            .replacingOccurrences(of: "\\", with: "\\\\")  // 先转义反斜杠
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        currentText = text
        isPlaying = true
        
        // 调用网页中的 sendSignText 函数
        let js = "if (typeof window.sendSignText === 'function') { window.sendSignText('\(cleanText)'); } else if (typeof sendSignText === 'function') { sendSignText('\(cleanText)'); }"
        
        print("[SignLanguageBridge] 发送文本: \(text.prefix(50))...")
        webView?.evaluateJavaScript(js) { [weak self] _, error in
            if let error = error {
                print("[SignLanguageBridge] JS执行错误: \(error.localizedDescription)")
            }
            Task { @MainActor in
                self?.isPlaying = false
            }
        }
    }
    
    /// 停止手语播放
    func stop() {
        isPlaying = false
        let js = "if (typeof window.stopSign === 'function') { window.stopSign(); } else if (typeof stopSign === 'function') { stopSign(); }"
        
        print("[SignLanguageBridge] 停止播放")
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
    
    /// 重新加载网页
    func reload() {
        isLoaded = false
        if let url = URL(string: signLanguageAvatarURL) {
            webView?.load(URLRequest(url: url))
        }
    }
}

// MARK: - SignLanguageWebView

/// 手语数字人 WebView 组件 - 使用 WKWebView 加载手语翻译服务
struct SignLanguageWebView: UIViewRepresentable {
    @ObservedObject var coordinator: AvatarCoordinator
    
    /// 初始化时要翻译的文本（可选）
    var initialText: String = ""
    
    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        
        // 注册消息处理器，用于接收网页的加载状态回调
        contentController.add(context.coordinator, name: "loadComplete")
        contentController.add(context.coordinator, name: "loadError")
        contentController.add(context.coordinator, name: "playbackComplete")
        contentController.add(context.coordinator, name: "debugLog")
        
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true  // 允许网页内的流式播放
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // 设置 WebView 背景色（浅灰色，确保可见）
        webView.isOpaque = true
        webView.backgroundColor = UIColor.systemGray6
        webView.scrollView.backgroundColor = UIColor.systemGray6
        webView.scrollView.isScrollEnabled = false
        
        // 启用调试日志
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        
        // 绑定 WebView 引用到协调器
        coordinator.webView = webView
        
        // 构建 URL 并加载
        var urlString = signLanguageAvatarURL
        if !initialText.isEmpty,
           let encodedText = initialText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "?text=\(encodedText)"
        }
        
        if let url = URL(string: urlString) {
            print("[SignLanguageWebView] 加载页面: \(url.absoluteString)")
            webView.load(URLRequest(url: url))
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // updateUIView 会在 SwiftUI 状态变化时调用
        // 这里不需要额外操作，文本更新通过 coordinator.sendText() 处理
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: WebViewCoordinator) {
        // 清理消息处理器，防止内存泄漏
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "loadComplete")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "loadError")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "playbackComplete")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "debugLog")
    }
    
    // MARK: - WebViewCoordinator
    
    class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: SignLanguageWebView
        
        init(_ parent: SignLanguageWebView) {
            self.parent = parent
        }
        
        // MARK: - WKScriptMessageHandler
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            Task { @MainActor in
                switch message.name {
                case "loadComplete":
                    print("[SignLanguageWebView] 数字人加载完成: \(message.body)")
                    self.parent.coordinator.isLoaded = true
                    
                case "loadError":
                    let errorMsg = message.body as? String ?? "未知错误"
                    print("[SignLanguageWebView] 加载错误: \(errorMsg)")
                    
                case "playbackComplete":
                    print("[SignLanguageWebView] 播放完成")
                    self.parent.coordinator.setPlaying(false)
                    
                case "debugLog":
                    print("[SignLanguageWebView-JS] \(message.body)")
                    
                default:
                    break
                }
            }
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[SignLanguageWebView] 页面加载完成")
            
            // 页面加载完成后，短暂延迟让 WebView 渲染，然后标记为已加载
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                if !self.parent.coordinator.isLoaded {
                    print("[SignLanguageWebView] 页面渲染完成，设置为已加载")
                    self.parent.coordinator.isLoaded = true
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[SignLanguageWebView] 导航失败: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[SignLanguageWebView] 预导航失败: \(error.localizedDescription)")
            print("[SignLanguageWebView] 错误详情: \(error)")
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("[SignLanguageWebView] 开始加载页面...")
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            print("[SignLanguageWebView] 页面内容开始到达...")
        }
        
        // 允许所有 HTTPS 请求
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

// MARK: - SignLanguageAvatarView

/// 手语数字人视图 - 直接显示网页
struct SignLanguageAvatarView: View {
    /// 要翻译的文本
    let textToTranslate: String
    
    /// 可选：外部传入的协调器（用于跨视图共享控制）
    var externalCoordinator: AvatarCoordinator?
    
    @StateObject private var internalCoordinator = AvatarCoordinator()
    
    /// 实际使用的协调器
    private var coordinator: AvatarCoordinator {
        externalCoordinator ?? internalCoordinator
    }
    
    var body: some View {
        SignLanguageWebView(
            coordinator: coordinator,
            initialText: textToTranslate
        )
    }
}

// MARK: - Preview

#Preview {
    SignLanguageAvatarView(textToTranslate: "你好，欢迎参观博物馆")
        .frame(height: 300)
}
