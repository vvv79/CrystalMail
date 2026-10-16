import SwiftUI
import WebKit

struct OWAWebLoginView: UIViewRepresentable {
    let serverUrl: String
    let login: String
    let password: String
    @Binding var status: String
    let onSuccess: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        let base = serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let url = URL(string: base + "/owa/auth/logon.aspx?url=" + base + "/owa/&reason=0") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: OWAWebLoginView
        private var timer: Timer?
        private var attempts = 0

        init(_ parent: OWAWebLoginView) { self.parent = parent }

        private var loginField: String { parent.login }

        private func jsEscape(_ s: String) -> String {
            return s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
        }

        // Certificate handling: trust our corporate CA (no per-device profile needed)
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.status = "Страница входа загружена" }
            injectCredentials(into: webView)
            startPolling(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.status = "SSL/ошибка загрузки: \(error.localizedDescription)" }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.status = "Ошибка: \(error.localizedDescription)" }
        }

        private func injectCredentials(into webView: WKWebView) {
            let user = jsEscape(loginField)
            let pass = jsEscape(parent.password)
            let js = """
            (function() {
                function fill(id, val) {
                    var el = document.getElementById(id) || document.querySelector('input[name="' + id + '"]');
                    if (el) { el.value = val; el.dispatchEvent(new Event('input', {bubbles:true})); el.dispatchEvent(new Event('change', {bubbles:true})); return true; }
                    return false;
                }
                fill('username','\(user)');
                fill('password','\(pass)');
                fill('loginfmt','\(user)');
                fill('passwd','\(pass)');
                if (typeof clkLgn === 'function') { setTimeout(function(){ clkLgn(); }, 300); return 'clkLgn'; }
                var btn = document.getElementById('SubmitCreds') || document.querySelector('input[type="submit"]') || document.querySelector('button[type="submit"]');
                if (btn) { setTimeout(function(){ btn.click(); }, 300); return 'btn'; }
                var f = document.logonForm || document.querySelector('form');
                if (f) { f.submit(); return 'form'; }
                return 'none';
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func startPolling(_ webView: WKWebView) {
            timer?.invalidate()
            attempts = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
                guard let self = self else { return }
                self.attempts += 1
                if self.attempts > 70 {
                    t.invalidate()
                    DispatchQueue.main.async { self.parent.onError("Не удалось войти") }
                    return
                }
                DispatchQueue.main.async { self.parent.status = "Ожидание входа... (\(self.attempts))" }
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    if cookies.contains(where: { $0.name == "X-OWA-CANARY" }) {
                        for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
                        t.invalidate()
                        let mailbox = self.parent.login
                        DispatchQueue.main.async { self.parent.onSuccess(mailbox) }
                    }
                }
            }
        }
    }
}
