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
                .disabled(serverMissing || fullLogin.isEmpty || password.isEmpty || loggingIn)
                .padding(.top, 8)

                if loggingIn {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(statusText.isEmpty ? "Вход..." : statusText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                if let error = app.errorMessage {
                    VStack(spacing: 8) {
                        Text(String(error.prefix(4)))
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)

                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.secondary)
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
        .onAppear {
            fullLogin = AppSettings.shared.fullLogin
            password = CredentialStore.shared.password
            if !fullLogin.isEmpty && !password.isEmpty {
                startLogin()
            }
        }
    }

    private var serverMissing: Bool {
        defaultServerUrl.isEmpty
    }

    private func startLogin() {
        guard !loggingIn else { return }
        loggingIn = true
        statusText = "Вход..."
        app.errorMessage = nil
        Task {
            let result = await app.login(
                serverUrl: defaultServerUrl,
                domain: defaultDomain,
                login: fullLogin,
                password: password
            )
            loggingIn = false
            if !result.0 {
                app.errorMessage = result.1
            }
        }
    }
}
