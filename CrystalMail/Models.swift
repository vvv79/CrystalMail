import Foundation

struct Recipient: Identifiable, Hashable {
    let id = UUID()
    var name: String = ""
    var emailAddress: String = ""
    var mailboxType: String = "Mailbox"

    static func == (lhs: Recipient, rhs: Recipient) -> Bool {
        lhs.emailAddress == rhs.emailAddress && lhs.name == rhs.name
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(emailAddress)
        hasher.combine(name)
    }
}

struct BodyContent {
    var contentType: String = "HTML"
    var content: String = ""
}

struct AttachmentId {
    var id: String = ""
    var rootItemId: String = ""
}

struct MailAttachment: Identifiable {
    let id = UUID()
    var name: String = ""
    var contentType: String = ""
    var contentId: String = ""
    var attachmentId: AttachmentId = AttachmentId()
    var size: Int = 0
    var isInline: Bool = false
}

struct MailItem: Identifiable {
    let id = UUID()
    var subject: String = ""
    var body: BodyContent = BodyContent()
    var toRecipients: [Recipient] = []
    var ccRecipients: [Recipient] = []
    var bccRecipients: [Recipient] = []
    var attachments: [MailAttachment] = []
    var from: Recipient? = nil
    var itemId: String = ""
    var parentFolderId: String = ""
    var isRead: Bool = true
    var receivedDateTime: String = ""
    var conversationId: String = ""
    var categories: [String] = []
    var hasAttachments: Bool = false
    var size: Int = 0
    var importance: String = "Normal"
    var sensitivity: String = "Normal"
}

struct ContactPerson: Identifiable {
    let id = UUID()
    var name: String = ""
    var emailAddress: String = ""
    var displayName: String = ""
    var mailboxType: String = "Mailbox"
    var routingType: String = "SMTP"
}

struct FolderInfo: Identifiable {
    var id: String = ""
    var displayName: String = ""
    var totalCount: Int = 0
    var unreadCount: Int = 0
    var childFolderCount: Int = 0
    var folderClass: String = ""
}

struct MailFolder: Identifiable {
    var id: String
    var name: String
    var symbol: String
    var unreadCount: Int = 0
}
