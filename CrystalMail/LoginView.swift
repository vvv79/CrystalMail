import SwiftUI

struct LoginView: View {
    @EnvironmentObject var app: AppState

    @State private var fullLogin = ""
    @State private var password = ""

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

                TextField("Логин (например DC1\\пользователь)", text: $fullLogin)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                SecureField("Пароль", text: $password)
                    .textFieldStyle(.roundedBorder)

                Button(action: submit) {
                    Text("Войти")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(fullLogin.isEmpty || password.isEmpty)
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            fullLogin = AppSettings.shared.fullLogin
            password = CredentialStore.shared.password
        }
    }

    private func submit() {
        guard !fullLogin.isEmpty, !password.isEmpty else { return }
        app.saveCredentials(
            serverUrl: defaultServerUrl,
            domain: defaultDomain,
            login: fullLogin,
            password: password
        )
    }
}
