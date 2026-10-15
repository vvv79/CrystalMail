import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = AppSettings.shared.isLoggedIn
    @Published var mails: [MailItem] = []
    @Published var currentMail: MailItem? = nil
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String? = nil
    @Published var hasMore = true
    @Published var statusText: String = ""

    private var currentFolderId = "inbox"
    private var currentOffset = 0
    private let pageSize = 50

    private func client() -> ExchangeApiClient {
        ExchangeApiClient(session: AppSettings.shared.currentSession())
    }

    func finishLogin(mailbox: String) {
        AppSettings.shared.mailbox = mailbox.isEmpty ? AppSettings.shared.fullLogin : mailbox
        isLoggedIn = true
    }

    func logout() {
        AppSettings.shared.clearSession()
        CredentialStore.shared.password = ""
        isLoggedIn = false
        mails = []
        currentMail = nil
    }

    func loadFolder(_ folderId: String) async {
        currentFolderId = folderId
        currentOffset = 0
        hasMore = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let json = try await client().findItems(folderId: folderId, maxCount: pageSize, offset: 0)
            let items = ExchangeJsonParser.parseNewMailItems(json)
            mails = items
            hasMore = items.count >= pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        currentOffset += pageSize
        defer { isLoadingMore = false }
        do {
            let json = try await client().findItems(folderId: currentFolderId, maxCount: pageSize, offset: currentOffset)
            let items = ExchangeJsonParser.parseNewMailItems(json)
            mails += items
            hasMore = items.count >= pageSize
        } catch {
            currentOffset -= pageSize
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await loadFolder(currentFolderId)
    }

    func loadMail(_ itemId: String) async {
        isLoading = true
        currentMail = nil
        errorMessage = nil
        defer { isLoading = false }
        do {
            let json = try await client().getMailItem(itemId: itemId)
            if let item = ExchangeJsonParser.parseMailItemDetail(json) {
                currentMail = item
                _ = try? await client().markAsRead(itemId: itemId)
                if let idx = mails.firstIndex(where: { $0.itemId == itemId }) {
                    mails[idx].isRead = true
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMail(
        subject: String,
        body: String,
        to: [Recipient],
        cc: [Recipient],
        bcc: [Recipient],
        attachments: [ExchangeApiClient.AttachmentFile]
    ) async -> (Bool, String) {
        isLoading = true
        defer { isLoading = false }
        do {
            let signature = AppSettings.shared.signature
            let fullBody = signature.isEmpty ? body : body + "<br>\n" + signature
            _ = try await client().sendMail(
                subject: subject,
                body: fullBody,
                toRecipients: to,
                ccRecipients: cc,
                bccRecipients: bcc,
                attachments: attachments
            )
            return (true, "Письмо отправлено")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func deleteMails(_ itemIds: [String]) async {
        let c = client()
        for id in itemIds { _ = try? await c.moveToDeleted(itemId: id) }
        mails = mails.filter { !itemIds.contains($0.itemId) }
    }

    func searchContacts(_ query: String) async -> [ContactPerson] {
        guard !query.isEmpty else { return [] }
        do {
            let json = try await client().findPeople(query: query)
            return ExchangeJsonParser.parseResolveNames(json)
        } catch {
            return []
        }
    }

    func attachmentBytes(itemId: String, attachmentId: String) async -> Data? {
        await client().getAttachmentBytes(itemId: itemId, attachmentId: attachmentId)
    }
}
