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
    
    /// 设置播放完成状态
    func setPlaybackComplete() {
        isPlaying = false
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

/// 手语数字人 WebView 组件 - 最简单的实现，直接显示网页
struct SignLanguageWebView: UIViewRepresentable {
    @ObservedObject var coordinator: AvatarCoordinator
    var initialText: String = ""

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        print("[SignLanguageWebView] ===== 开始创建 WKWebView =====")

        // 创建内容控制器 - 用于双向通信
        let contentController = WKUserContentController()
        // 注册消息处理器，网页通过 window.webkit.messageHandlers.xxx.postMessage() 发送消息
        contentController.add(context.coordinator, name: "loadComplete")
        contentController.add(context.coordinator, name: "loadError")
        contentController.add(context.coordinator, name: "playbackComplete")
        contentController.add(context.coordinator, name: "debugLog")
        print("[SignLanguageWebView] 消息处理器已注册")

        // 创建配置
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // 启用 JavaScript
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences = preferences

        // 创建 WebView
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // 禁用滚动
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false

        print("[SignLanguageWebView] WKWebView 实例创建完成")

        // 绑定到 coordinator（必须在加载前完成）
        coordinator.webView = webView
        print("[SignLanguageWebView] Coordinator 已绑定")

        // 加载 URL
        if let url = URL(string: signLanguageAvatarURL) {
            print("[SignLanguageWebView] 🌐 开始加载: \(signLanguageAvatarURL)")
            webView.load(URLRequest(url: url))
        } else {
            print("[SignLanguageWebView] ❌ URL 无效")
        }

        print("[SignLanguageWebView] ===== 创建完成 =====")

        return webView
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: WebViewCoordinator) {
        // 清理消息处理器，防止内存泄漏
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "loadComplete")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "loadError")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "playbackComplete")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "debugLog")
        print("[SignLanguageWebView] 消息处理器已清理")
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: SignLanguageWebView

        init(_ parent: SignLanguageWebView) {
            self.parent = parent
            super.init()
        }

        // MARK: - WKScriptMessageHandler (接收网页消息)

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            DispatchQueue.main.async {
                switch message.name {
                case "loadComplete":
                    print("[WebView] 📢 网页回调: loadComplete - \(message.body)")
                    self.parent.coordinator.isLoaded = true

                    // 网页就绪后发送初始文本
                    if !self.parent.initialText.isEmpty {
                        print("[WebView] 📤 网页就绪，发送初始文本")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.parent.coordinator.sendText(self.parent.initialText)
                        }
                    }

                case "loadError":
                    let errorMsg = message.body as? String ?? "未知错误"
                    print("[WebView] ❌ 网页回调: loadError - \(errorMsg)")

                case "playbackComplete":
                    print("[WebView] ✅ 网页回调: playbackComplete")
                    self.parent.coordinator.setPlaybackComplete()

                case "debugLog":
                    print("[WebView-JS] 📝 \(message.body)")

                default:
                    break
                }
            }
        }

        // MARK: - WKNavigationDelegate

        // 导航开始
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("[WebView] 🚀 开始导航")
        }

        // 导航完成（页面 HTML 加载完成，但 SDK 可能还在初始化）
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[WebView] ✅ 页面 HTML 加载完成，等待网页就绪通知...")

            // 超时保护：如果 5 秒后还没收到 loadComplete，设置为已加载
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if !self.parent.coordinator.isLoaded {
                    print("[WebView] ⏱️ 超时，强制设置为已加载")
                    self.parent.coordinator.isLoaded = true
                }
            }
        }

        // 导航失败
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            print("[WebView] ❌ 导航失败: \(error.localizedDescription)")
            print("[WebView] 错误代码: \(nsError.code), 域: \(nsError.domain)")
        }

        // 预导航失败（通常是网络问题）
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            print("[WebView] ❌ 预导航失败: \(error.localizedDescription)")
            print("[WebView] 错误代码: \(nsError.code), 域: \(nsError.domain)")

            // 常见错误处理
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorTimedOut:
                    print("[WebView] ⏱️ 请求超时")
                case NSURLErrorNotConnectedToInternet:
                    print("[WebView] 📡 无网络连接")
                case NSURLErrorCannotConnectToHost:
                    print("[WebView] 🔌 无法连接到主机")
                default:
                    break
                }
            }
        }

        // 收到服务器重定向
        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            if let url = webView.url {
                print("[WebView] ↪️ 重定向到: \(url.absoluteString)")
            }
        }

        // 决定导航策略
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                print("[WebView] 🔗 请求 URL: \(url.absoluteString)")
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - SignLanguageAvatarView

/// 手语数字人视图 - 直接显示网页，无蒙版
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
        .onChange(of: textToTranslate) { _, newValue in
            // 当文本变化时，自动发送到数字人
            if coordinator.isLoaded && !newValue.isEmpty {
                coordinator.sendText(newValue)
            }
        }
        .onChange(of: coordinator.isLoaded) { _, isLoaded in
            // 当数字人加载完成时，发送初始文本
            if isLoaded && !textToTranslate.isEmpty {
                coordinator.sendText(textToTranslate)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SignLanguageAvatarView(textToTranslate: "你好，欢迎参观博物馆")
        .frame(height: 300)
}
