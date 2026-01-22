import SwiftUI
import WebKit

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
        
        // 允许 WebGL
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        // 存储 webView 引用以便后续使用
        context.coordinator.webView = webView
        
        // 加载手语数字人 HTML - 使用网络 URL 作为 baseURL 以支持 ES Module
        let html = generateSignLanguageHTML(text: textToTranslate)
        if let baseURL = URL(string: "https://avatar.gbqr.net/") {
            webView.loadHTMLString(html, baseURL: baseURL)
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // 文本变化时不重新加载，由 JS 内部处理
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 清理消息处理器，防止内存泄漏
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "loadComplete")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "loadError")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "debugLog")
    }
    
    private func escapeJavaScript(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
    
    private func generateSignLanguageHTML(text: String) -> String {
        let appSecret = Secrets.shared.signLanguageAppSecret ?? ""
        let escapedText = escapeJavaScript(text)
        
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
                html, body {
                    width: 100%;
                    height: 100%;
                    overflow: hidden;
                    background: transparent;
                }
                body {
                    display: flex;
                    justify-content: center;
                    align-items: center;
                }
                #yiyuAppElement {
                    position: relative !important;
                    top: auto !important;
                    left: auto !important;
                    transform: none !important;
                }
                canvas, video {
                    max-width: 100% !important;
                    max-height: 100% !important;
                    object-fit: contain;
                }
            </style>
        </head>
        <body>
            <script type="module">
                // 调试日志函数
                function log(msg) {
                    console.log('[SignLanguage]', msg);
                    try {
                        window.webkit.messageHandlers.debugLog.postMessage(msg);
                    } catch (e) {}
                }
                
                // 安全地发送消息到 iOS
                function postMessage(handler, msg) {
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[handler]) {
                            window.webkit.messageHandlers[handler].postMessage(msg);
                        }
                    } catch (e) {
                        console.error('postMessage error:', e);
                    }
                }
                
                // 动态加载 SDK
                async function loadSDK() {
                    log('开始加载 SDK...');
                    
                    try {
                        // 动态导入 SDK
                        const module = await import('https://avatar.gbqr.net/yiyu.js');
                        log('SDK 模块加载成功');
                        
                        // 等待 yiyu 全局对象可用
                        let attempts = 0;
                        const maxAttempts = 50;
                        
                        while (typeof yiyu === 'undefined' && attempts < maxAttempts) {
                            await new Promise(r => setTimeout(r, 100));
                            attempts++;
                        }
                        
                        if (typeof yiyu === 'undefined') {
                            throw new Error('yiyu 对象未定义，SDK 加载超时');
                        }
                        
                        log('yiyu 对象可用，开始初始化...');
                        
                        // 初始化数字人
                        yiyu.app.init({
                            name: '\(appSecret)',
                            readLocalResource: false
                        });
                        
                        log('初始化完成，等待渲染...');
                        
                        // 等待 canvas 创建
                        await new Promise(r => setTimeout(r, 2000));
                        
                        // 检查是否有 canvas
                        const canvas = document.querySelector('canvas');
                        if (canvas) {
                            log('Canvas 已创建: ' + canvas.width + 'x' + canvas.height);
                        } else {
                            log('警告: 未找到 canvas 元素');
                        }
                        
                        // 开始翻译
                        const text = '\(escapedText)';
                        if (text.trim() !== '') {
                            log('开始翻译: ' + text.substring(0, 20) + '...');
                            yiyu.app.startTranslate(text);
                        }
                        
                        // 通知 iOS 加载完成
                        postMessage('loadComplete', 'success');
                        
                    } catch (e) {
                        log('错误: ' + e.message);
                        postMessage('loadError', e.message || 'unknown error');
                    }
                }
                
                // 全局错误处理
                window.onerror = function(msg, url, line, col, error) {
                    log('JS Error: ' + msg);
                    postMessage('loadError', msg);
                    return true;
                };
                
                // 启动加载
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', loadSDK);
                } else {
                    loadSDK();
                }
            </script>
        </body>
        </html>
        """
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
