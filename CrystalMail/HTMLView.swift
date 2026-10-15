import SwiftUI
import WebKit

struct HTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let doc = """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>body{font-family:-apple-system;font-size:16px;margin:8px;word-wrap:break-word;} img{max-width:100%;height:auto;}</style>
        </head><body>\(html)</body></html>
        """
        webView.loadHTMLString(doc, baseURL: nil)
    }
}
