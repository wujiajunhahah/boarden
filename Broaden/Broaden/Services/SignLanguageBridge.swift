import SwiftUI
import WebKit

/// 手语数字人在线页面 URL
private let signLanguageAvatarURL = "https://ios-avatar-web.vercel.app"

// MARK: - AvatarCoordinator

/// 手语数字人协调器 - 作为控制数字人的"遥控器"
/// 可以被多个视图共享，用于发送手语脚本、停止播放等操作
class AvatarCoordinator: ObservableObject {
    weak var webView: WKWebView?
    
    /// 当前正在翻译的文本
    @Published private(set) var currentText: String = ""
    
    /// WebView 是否已加载完成
    @Published var isLoaded: Bool = false
    
    /// 是否正在播放
    @Published private(set) var isPlaying: Bool = false
    
    /// 发送手语脚本到数字人
    /// - Parameter text: 要翻译的文本内容
    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        
        // 清理文本，防止换行符和引号导致 JS 语法错误
        let cleanText = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\\", with: "\\\\")
        
        currentText = text
        isPlaying = true
        
        // 调用网页中的 sendSignText 函数
        let js = "if (typeof window.sendSignText === 'function') { window.sendSignText('\(cleanText)'); } else if (typeof sendSignText === 'function') { sendSignText('\(cleanText)'); }"
        
        print("[SignLanguageBridge] 发送文本: \(text.prefix(50))...")
        webView?.evaluateJavaScript(js) { [weak self] _, error in
            if let error = error {
                print("[SignLanguageBridge] JS执行错误: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
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
        
        // 核心：让 WebView 本身变得完全透明且不可滚动
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        
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
            DispatchQueue.main.async {
                switch message.name {
                case "loadComplete":
                    print("[SignLanguageWebView] 数字人加载完成: \(message.body)")
                    self.parent.coordinator.isLoaded = true
                    
                case "loadError":
                    let errorMsg = message.body as? String ?? "未知错误"
                    print("[SignLanguageWebView] 加载错误: \(errorMsg)")
                    
                case "playbackComplete":
                    print("[SignLanguageWebView] 播放完成")
                    self.parent.coordinator.isPlaying = false
                    
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
            
            // 超时保护：如果 10 秒后还没收到 loadComplete，自动设置为已加载
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if !self.parent.coordinator.isLoaded {
                    print("[SignLanguageWebView] 加载超时，强制设置为已加载")
                    self.parent.coordinator.isLoaded = true
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[SignLanguageWebView] 导航失败: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[SignLanguageWebView] 预导航失败: \(error.localizedDescription)")
        }
        
        // 允许所有 HTTPS 请求
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

// MARK: - SignLanguageAvatarView

/// 手语数字人视图 - 带有加载状态和错误处理的完整组件
struct SignLanguageAvatarView: View {
    /// 要翻译的文本
    let textToTranslate: String
    
    /// 可选：外部传入的协调器（用于跨视图共享控制）
    var externalCoordinator: AvatarCoordinator?
    
    @StateObject private var internalCoordinator = AvatarCoordinator()
    @State private var hasError = false
    @State private var errorMessage = ""
    
    /// 实际使用的协调器
    private var coordinator: AvatarCoordinator {
        externalCoordinator ?? internalCoordinator
    }
    
    var body: some View {
        ZStack {
            // 数字人 WebView 层
            SignLanguageWebView(
                coordinator: coordinator,
                initialText: textToTranslate
            )
            
            // 加载中遮罩
            if !coordinator.isLoaded {
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
            
            // 错误遮罩
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
                    Button("重试") {
                        hasError = false
                        coordinator.reload()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial)
            }
        }
        .onChange(of: textToTranslate) { _, newValue in
            // 当文本变化时，自动发送到数字人
            if coordinator.isLoaded && !newValue.isEmpty {
                coordinator.sendText(newValue)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SignLanguageAvatarView(textToTranslate: "你好，欢迎参观博物馆")
        .frame(height: 300)
}
