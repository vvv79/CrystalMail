import Foundation
import WebKit
import UIKit

@MainActor
final class WebTransport: NSObject, WKNavigationDelegate {
    static let shared = WebTransport()

    private var webView: WKWebView?
    private var baseUrl = ""
    private(set) var isReady = false
    private(set) var statusText = "не запущен"

    private override init() { super.init() }

    func start(serverUrl: String) {
        guard webView == nil else { return }
        baseUrl = serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        statusText = "запуск"

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: CGRect(x: 1, y: 1, width: 2, height: 2), configuration: config)
        wv.navigationDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.customUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        webView = wv
        attachToWindow(wv)

        let store = wv.configuration.websiteDataStore.httpCookieStore
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let group = DispatchGroup()
        for c in cookies {
            group.enter()
            store.setCookie(c) { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            if let url = URL(string: self.baseUrl + "/owa/") {
                wv.load(URLRequest(url: url))
            }
        }
    }

    private func attachToWindow(_ wv: WKWebView) {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        if let window = window {
            wv.frame = CGRect(x: 1, y: 1, width: 2, height: 2)
            wv.alpha = 0.01
            window.addSubview(wv)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        statusText = "готов"
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isReady = true
        statusText = "ошибка: \(error.localizedDescription)"
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isReady = true
        statusText = "ошибка: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            var anchors = ExchangeApiClient.trustAnchors()
            if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
                anchors.append(contentsOf: chain)
            }
            if !anchors.isEmpty {
                SecTrustSetAnchorCertificates(trust, anchors as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, false)
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private func canary() -> String {
        if let url = URL(string: baseUrl),
           let c = HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == "X-OWA-CANARY" }) {
            return c.value
        }
        if let c = HTTPCookieStorage.shared.cookies?.first(where: { $0.name == "X-OWA-CANARY" }) {
            return c.value
        }
        return ""
    }

    func apiCall(endpoint: String, body: String) async -> String {
        if webView == nil { return "" }
        // wait a bit for the web view to be ready
        var waited = 0
        while webView == nil || !isReady {
            if waited > 40 { return "" } // ~4s
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        guard let webView = webView else { return "" }

        let bodyB64 = Data(body.utf8).base64EncodedString()
        let canaryValue = canary().replacingOccurrences(of: "'", with: "")
        let js = """
        (function(){
          try {
            var xhr = new XMLHttpRequest();
            xhr.open('POST', '\(endpoint)', false);
            xhr.setRequestHeader('Content-Type','application/json; charset=utf-8');
            xhr.setRequestHeader('X-OWA-CANARY','\(canaryValue)');
            var bin = atob('\(bodyB64)');
            var bytes = new Uint8Array(bin.length);
            for (var i=0;i<bin.length;i++){ bytes[i]=bin.charCodeAt(i); }
            var reqBody = new TextDecoder('utf-8').decode(bytes);
            xhr.send(reqBody);
            var text = xhr.responseText || '';
            var enc = new TextEncoder().encode(text);
            var b = '';
            for (var i=0;i<enc.length;i++){ b += String.fromCharCode(enc[i]); }
            return btoa(b);
          } catch(e) { return 'ERR:' + e; }
        })();
        """
        let result = await evaluate(webView, js)
        if let r = result, let data = Data(base64Encoded: r), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return result ?? ""
    }

    private func evaluate(_ webView: WKWebView, _ js: String) async -> String? {
        return await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                webView.evaluateJavaScript(js) { value, _ in
                    cont.resume(returning: value as? String)
                }
            }
        }
    }
}
