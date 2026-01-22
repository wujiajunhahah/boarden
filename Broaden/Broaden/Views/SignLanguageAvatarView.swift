import SwiftUI
import WebKit

/// 手语数字人视图 - 使用 WKWebView 加载手语翻译服务
struct SignLanguageAvatarView: View {
    let textToTranslate: String
    
    @State private var isLoading = true
    @State private var hasError = false
    
    var body: some View {
        ZStack {
            SignLanguageWebView(
                textToTranslate: textToTranslate,
                isLoading: $isLoading,
                hasError: $hasError
            )
            
            if isLoading {
                ProgressView("加载手语数字人...")
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
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        // 加载手语数字人 HTML
        let html = generateSignLanguageHTML(text: textToTranslate)
        webView.loadHTMLString(html, baseURL: nil)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // 当文本变化时，触发翻译
        let script = "if (typeof yiyu !== 'undefined' && yiyu.app) { yiyu.app.startTranslate('\(escapeJavaScript(textToTranslate))'); }"
        webView.evaluateJavaScript(script, completionHandler: nil)
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
            <script type="module" src="https://avatar.gbqr.net/yiyu.js"></script>
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
                canvas, video {
                    max-width: 100% !important;
                    max-height: 100% !important;
                    object-fit: contain;
                }
            </style>
        </head>
        <body>
            <script>
                window.addEventListener('load', function() {
                    try {
                        yiyu.app.init({
                            name: '\(appSecret)',
                            readLocalResource: false
                        });
                        
                        // 初始化完成后自动开始翻译
                        setTimeout(function() {
                            if ('\(escapedText)'.trim() !== '') {
                                yiyu.app.startTranslate('\(escapedText)');
                            }
                            // 通知 iOS 加载完成
                            window.webkit.messageHandlers.loadComplete.postMessage('success');
                        }, 1000);
                    } catch (e) {
                        console.error('手语数字人初始化失败:', e);
                        window.webkit.messageHandlers.loadError.postMessage(e.message || 'unknown error');
                    }
                });
                
                window.addEventListener('error', function(e) {
                    window.webkit.messageHandlers.loadError.postMessage(e.message || 'unknown error');
                });
            </script>
        </body>
        </html>
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SignLanguageWebView
        
        init(_ parent: SignLanguageWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 给 JS SDK 一些时间初始化
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.parent.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.hasError = true
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.hasError = true
        }
    }
}

#Preview {
    SignLanguageAvatarView(textToTranslate: "你好，欢迎参观博物馆")
        .frame(height: 300)
}
