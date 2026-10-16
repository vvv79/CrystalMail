import SwiftUI
import WebKit

struct OWAWebApp: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack(alignment: .topTrailing) {
            OWAWebView(
                serverUrl: AppSettings.shared.serverUrl.isEmpty ? "https://mail.crystal-management.kz" : AppSettings.shared.serverUrl,
                login: AppSettings.shared.fullLogin,
                password: CredentialStore.shared.password
            )
            .ignoresSafeArea()

            Button {
                app.logoutWeb()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .padding(10)
                    .background(Color(.systemBackground).opacity(0.75))
                    .clipShape(Circle())
            }
            .padding(10)
        }
    }
}

struct OWAWebView: UIViewRepresentable {
    let serverUrl: String
    let login: String
    let password: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // keep the session between launches
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        let base = serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let url = URL(string: base + "/owa/") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: OWAWebView
        private var didAutoSubmit = false

        init(_ parent: OWAWebView) { self.parent = parent }

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
            guard !didAutoSubmit else { return }
            guard !parent.login.isEmpty, !parent.password.isEmpty else { return }
            webView.evaluateJavaScript("document.querySelector('input[type=password]') != null") { [weak self] result, _ in
                guard let self = self else { return }
                if let has = result as? Bool, has {
                    self.didAutoSubmit = true
                    self.fill(webView)
                }
            }
        }

        private func jsEscape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
        }

        private func fill(_ webView: WKWebView) {
            let user = jsEscape(parent.login)
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
    }
}
