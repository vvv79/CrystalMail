import SwiftUI
import WebKit

struct LoginView: View {
    @EnvironmentObject var app: AppState

    @State private var serverUrl = ""
    @State private var domain = ""
    @State private var fullLogin = ""
    @State private var password = ""
    @State private var loggingIn = false
    @State private var statusText = ""

    private let defaultServerUrl = "https://mail.crystal-management.kz"
    private let defaultDomain = "DC1"

    var body: some View {
        ZStack {
            if loggingIn {
                OWAWebLoginView(
                    serverUrl: serverUrl,
                    login: fullLogin,
                    password: password,
                    status: $statusText,
                    onSuccess: { mailbox in
                        loggingIn = false
                        app.finishLogin(mailbox: mailbox)
                    },
                    onError: { message in
                        loggingIn = false
                        app.errorMessage = message
                    }
                )
                .ignoresSafeArea()

                VStack {
                    Text(statusText)
                        .font(.footnote)
                        .padding(8)
                        .background(Color(.systemBackground).opacity(0.9))
                        .cornerRadius(8)
                        .padding(.top, 8)
                    Spacer()
                }
            } else {
                form
            }
        }
        .onAppear {
            serverUrl = defaultServerUrl
            domain = defaultDomain
            fullLogin = AppSettings.shared.fullLogin
            password = CredentialStore.shared.password
            if !fullLogin.isEmpty && !password.isEmpty {
                startLogin()
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("CrystalMail")
                    .font(.largeTitle).bold()
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Вход в Exchange")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 12)

                TextField("Логин", text: $fullLogin)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                SecureField("Пароль", text: $password)
                    .textFieldStyle(.roundedBorder)

                Button(action: startLogin) {
                    Text("Войти")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverUrl.isEmpty || fullLogin.isEmpty || password.isEmpty)
                .padding(.top, 8)

                if let error = app.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func startLogin() {
        AppSettings.shared.serverUrl = serverUrl.trimmingCharacters(in: .whitespaces)
        AppSettings.shared.domain = domain
        AppSettings.shared.fullLogin = fullLogin
        CredentialStore.shared.password = password
        app.errorMessage = nil
        statusText = "Выполняется вход..."
        loggingIn = true
    }
}

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

        init(_ parent: OWAWebLoginView) {
            self.parent = parent
        }

        private var loginField: String {
            if let at = parent.login.firstIndex(of: "@") {
                return String(parent.login[parent.login.startIndex..<at])
            }
            return parent.login
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            injectCredentials(into: webView)
            startPolling(webView)
        }

        private func jsEscape(_ s: String) -> String {
            return s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
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
                if self.attempts > 80 {
                    t.invalidate()
                    DispatchQueue.main.async { self.parent.onError("Не удалось авторизоваться. Проверьте логин/пароль") }
                    return
                }
                DispatchQueue.main.async { self.parent.status = "Ожидание входа... (\(self.attempts))" }
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    if let canary = cookies.first(where: { $0.name == "X-OWA-CANARY" }) {
                        _ = canary
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
