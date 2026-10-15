import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    @State private var unitySignature = ""
    @State private var notificationsEnabled = true
    @State private var showSubject = true

    var body: some View {
        Form {
            Section("Уведомления") {
                Toggle("Включить уведомления", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { AppSettings.shared.notificationsEnabled = $0 }
                Toggle("Показывать тему", isOn: $showSubject)
                    .onChange(of: showSubject) { AppSettings.shared.showSubjectInNotification = $0 }
            }

            Section("Подпись") {
                TextEditor(text: $unitySignature)
                    .frame(minHeight: 90)
                    .onChange(of: unitySignature) { AppSettings.shared.signature = $0 }
            }

            Section("Аккаунт") {
                LabeledContentCompat(label: "Почта", value: AppSettings.shared.mailbox)
                LabeledContentCompat(label: "Сервер", value: AppSettings.shared.serverUrl)
            }

            Section {
                Button(role: .destructive, action: { app.logout() }) {
                    Text("Выйти из аккаунта")
                }
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            unitySignature = AppSettings.shared.signature
            notificationsEnabled = AppSettings.shared.notificationsEnabled
            showSubject = AppSettings.shared.showSubjectInNotification
        }
    }
}

struct LabeledContentCompat: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
