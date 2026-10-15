import SwiftUI

struct MailDetailView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.presentationMode) var presentationMode
    let itemId: String

    @State private var loaded = false

    var body: some View {
        Group {
            if app.isLoading && app.currentMail == nil {
                ProgressView("Загрузка...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let mail = app.currentMail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(mail.subject.isEmpty ? "(без темы)" : mail.subject)
                            .font(.title3).bold()

                        HStack(spacing: 6) {
                            Text(mail.from?.name.isEmpty == false ? mail.from!.name : (mail.from?.emailAddress ?? ""))
                                .bold()
                            Text("<\(mail.from?.emailAddress ?? "")>")
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .font(.subheadline)

                        Text(mail.receivedDateTime)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !mail.toRecipients.isEmpty {
                            Text("Кому: " + mail.toRecipients.map { $0.emailAddress }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if !mail.attachments.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(mail.attachments) { att in
                                    Label(att.name, systemImage: "paperclip").font(.footnote)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Divider()

                        HTMLView(html: mail.body.content.isEmpty ? "<p>(пустое письмо)</p>" : mail.body.content)
                            .frame(minHeight: 320)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 8) {
                    Text("Не удалось загрузить письмо").foregroundColor(.secondary)
                    if let err = app.errorMessage { Text(err).font(.footnote).foregroundColor(.red) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Письмо")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                NavigationLink(destination: ComposeView(mode: .reply, replyTo: app.currentMail)) {
                    Image(systemName: "arrowshape.turn.up.left")
                }
                NavigationLink(destination: ComposeView(mode: .forward, replyTo: app.currentMail)) {
                    Image(systemName: "arrowshape.turn.up.right")
                }
                Button(action: deleteMail) {
                    Image(systemName: "trash")
                }
            }
        }
        .onAppear {
            if !loaded {
                loaded = true
                Task { await app.loadMail(itemId) }
            }
        }
    }

    private func deleteMail() {
        Task {
            await app.deleteMails([itemId])
            presentationMode.wrappedValue.dismiss()
        }
    }
}
