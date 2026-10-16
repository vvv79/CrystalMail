import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject var app: AppState

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
                    serverUrl: defaultServerUrl,
                    login: fullLogin,
                    password: password,
                    status: $statusText,
                    onSuccess: { mailbox in
                        loggingIn = false
                        AppSettings.shared.serverUrl = defaultServerUrl
                        AppSettings.shared.domain = defaultDomain
                        AppSettings.shared.fullLogin = fullLogin
                        CredentialStore.shared.password = password
                        WebTransport.shared.start(serverUrl: defaultServerUrl)
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
                Text("Вход в корпоративную почту")
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
                .disabled(fullLogin.isEmpty || password.isEmpty || loggingIn)
                .padding(.top, 8)

                Button("Открыть OWA в Safari") {
                    if let url = URL(string: defaultServerUrl + "/owa/") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .center)

                if let error = app.errorMessage {
                    VStack(spacing: 8) {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                        Button("Скопировать текст ошибки") {
                            UIPasteboard.general.string = error
                        }
                        .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func startLogin() {
        guard !loggingIn else { return }
        AppSettings.shared.serverUrl = defaultServerUrl
        AppSettings.shared.domain = defaultDomain
        AppSettings.shared.fullLogin = fullLogin
        CredentialStore.shared.password = password
        app.errorMessage = nil
        statusText = "Выполняется вход..."
        loggingIn = true
    }
}
