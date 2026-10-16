import SwiftUI
import UIKit

struct MailListView: View {
    @EnvironmentObject var app: AppState
    let folderId: String
    let folderName: String

    @State private var loaded = false

    var body: some View {
        Group {
            if app.isLoading && app.mails.isEmpty {
                ProgressView("Загрузка...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if app.mails.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Писем нет").foregroundColor(.secondary)
                    if let err = app.errorMessage {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .textSelection(.enabled)
                        Button("Скопировать текст") {
                            UIPasteboard.general.string = err
                        }
                        .font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(app.mails) { mail in
                        NavigationLink(destination: MailDetailView(itemId: mail.itemId)) {
                            MailRowView(mail: mail)
                        }
                    }
                    if app.hasMore {
                        HStack {
                            Spacer()
                            if app.isLoadingMore { ProgressView() }
                            else { Button("Показать ещё") { Task { await app.loadMore() } } }
                            Spacer()
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(folderName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: ComposeView(mode: .new, replyTo: nil)) {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .refreshable { await app.refresh() }
        .onAppear {
            if !loaded {
                loaded = true
                Task { await app.loadFolder(folderId) }
            }
        }
    }
}

struct MailRowView: View {
    let mail: MailItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(mail.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(mail.from?.name.isEmpty == false ? mail.from!.name : (mail.from?.emailAddress ?? "—"))
                        .font(.subheadline).bold()
                        .lineLimit(1)
                    Spacer()
                    Text(shortDate(mail.receivedDateTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(mail.subject.isEmpty ? "(без темы)" : mail.subject)
                    .font(.subheadline)
                    .lineLimit(1)
                if mail.hasAttachments {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func shortDate(_ iso: String) -> String {
        guard !iso.isEmpty else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let d = date else { return String(iso.prefix(10)) }
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df.string(from: d)
    }
}
