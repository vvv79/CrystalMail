import SwiftUI

enum ComposeMode {
    case new
    case reply
    case forward
}

struct ComposeView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.presentationMode) var presentationMode
    let mode: ComposeMode
    let replyTo: MailItem?

    @State private var toText = ""
    @State private var ccText = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var sending = false
    @State private var infoMessage: String?
    @State private var didPrefill = false

    var body: some View {
        Form {
            Section {
                TextField("Кому (через запятую)", text: $toText)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.emailAddress)
                TextField("Копия (через запятую)", text: $ccText)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.emailAddress)
                TextField("Тема", text: $subject)
            }

            Section("Текст") {
                TextEditor(text: $bodyText)
                    .frame(minHeight: 220)
            }

            if let infoMessage = infoMessage {
                Section {
                    Text(infoMessage).foregroundColor(.red).font(.footnote)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if sending {
                    ProgressView()
                } else {
                    Button("Отправить", action: send)
                        .disabled(toText.isEmpty || sending)
                }
            }
        }
        .onAppear(perform: prefill)
    }

    private var title: String {
        switch mode {
        case .new: return "Новое письмо"
        case .reply: return "Ответ"
        case .forward: return "Пересылка"
        }
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        guard let mail = replyTo else { return }

        let prefix: String
        switch mode {
        case .reply:
            toText = mail.from?.emailAddress ?? ""
            prefix = "Re: "
        case .forward:
            prefix = "Fwd: "
        case .new:
            prefix = ""
        }
        subject = mail.subject.hasPrefix(prefix) ? mail.subject : prefix + mail.subject

        let quoted = """
        <br><br><hr>
        <b>От:</b> \(mail.from?.name ?? "") &lt;\(mail.from?.emailAddress ?? "")&gt;<br>
        <b>Дата:</b> \(mail.receivedDateTime)<br>
        <b>Тема:</b> \(mail.subject)<br><br>
        \(mail.body.content)
        """
        bodyText = quoted
    }

    private func parseRecipients(_ text: String) -> [Recipient] {
        text.split(separator: ",").map { part in
            let t = part.trimmingCharacters(in: .whitespaces)
            return Recipient(name: t, emailAddress: t)
        }.filter { !$0.emailAddress.isEmpty }
    }

    private func send() {
        sending = true
        infoMessage = nil
        let to = parseRecipients(toText)
        let cc = parseRecipients(ccText)
        Task {
            let result = await app.sendMail(
                subject: subject,
                body: bodyText.replacingOccurrences(of: "\n", with: "<br>"),
                to: to,
                cc: cc,
                bcc: [],
                attachments: []
            )
            sending = false
            if result.0 {
                presentationMode.wrappedValue.dismiss()
            } else {
                infoMessage = result.1
            }
        }
    }
}
