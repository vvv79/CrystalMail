import Foundation

enum ExchangeJsonParser {

    static func parseNewMailItems(_ json: String) -> [MailItem] {
        var list: [MailItem] = []
        if let data = json.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for obj in arr { list.append(parseMailItem(obj)) }
            return list
        }
        if let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = obj["value"] as? [[String: Any]] {
            for item in arr { list.append(parseMailItem(item)) }
        }
        return list
    }

    static func parseMailItemDetail(_ json: String) -> MailItem? {
        if let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseMailItem(obj)
        }
        if let data = json.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = arr.first {
            return parseMailItem(first)
        }
        return nil
    }

    private static func str(_ obj: [String: Any], _ key: String, _ fallback: String = "") -> String {
        if let v = obj[key] as? String { return v }
        if let v = obj[key] as? NSNumber { return v.stringValue }
        return fallback
    }

    private static func parseMailItem(_ obj: [String: Any]) -> MailItem {
        var item = MailItem()

        if let attArr = obj["attachments"] as? [[String: Any]] {
            for att in attArr {
                let attIdDict = att["attachmentId"] as? [String: Any]
                let aId = AttachmentId(
                    id: str(att, "attachmentId", attIdDict?["id"] as? String ?? str(att, "id")),
                    rootItemId: str(att, "rootItemId", str(obj, "itemId"))
                )
                item.attachments.append(MailAttachment(
                    name: str(att, "name"),
                    contentType: str(att, "contentType"),
                    contentId: str(att, "contentId"),
                    attachmentId: aId,
                    size: (att["size"] as? NSNumber)?.intValue ?? 0,
                    isInline: att["isInline"] as? Bool ?? false
                ))
            }
        }

        item.toRecipients = parseRecipients(obj["toRecipients"] as? [[String: Any]])
        item.ccRecipients = parseRecipients(obj["ccRecipients"] as? [[String: Any]])
        item.bccRecipients = parseRecipients(obj["bccRecipients"] as? [[String: Any]])

        if let f = obj["from"] as? [String: Any] {
            item.from = Recipient(name: str(f, "name"), emailAddress: str(f, "emailAddress"))
        }

        if let catArr = obj["categories"] as? [String] {
            item.categories = catArr
        }

        let bodyObj = obj["body"] as? [String: Any]
        item.subject = str(obj, "subject")
        item.body = BodyContent(
            contentType: (bodyObj?["contentType"] as? String) ?? "HTML",
            content: (bodyObj?["content"] as? String) ?? ""
        )
        item.itemId = str(obj, "itemId", str(obj, "id"))
        item.parentFolderId = str(obj, "parentFolderId", str(obj, "folderId"))
        item.isRead = obj["isRead"] as? Bool ?? true
        item.receivedDateTime = str(obj, "receivedDateTime", str(obj, "dateTime"))
        item.conversationId = str(obj, "conversationId", str(obj, "conversationIdValue"))
        item.hasAttachments = obj["hasAttachments"] as? Bool ?? !item.attachments.isEmpty
        item.size = (obj["size"] as? NSNumber)?.intValue ?? 0
        item.importance = str(obj, "importance", "Normal")
        item.sensitivity = str(obj, "sensitivity", "Normal")
        return item
    }

    private static func parseRecipients(_ arr: [[String: Any]]?) -> [Recipient] {
        guard let arr = arr else { return [] }
        var list: [Recipient] = []
        for obj in arr {
            if let mailbox = obj["mailbox"] as? [String: Any] {
                list.append(Recipient(
                    name: str(mailbox, "name"),
                    emailAddress: str(mailbox, "emailAddress"),
                    mailboxType: str(mailbox, "mailboxType", "Mailbox")
                ))
            } else {
                list.append(Recipient(
                    name: str(obj, "name"),
                    emailAddress: str(obj, "emailAddress"),
                    mailboxType: str(obj, "mailboxType", "Mailbox")
                ))
            }
        }
        return list
    }

    static func parseResolveNames(_ json: String) -> [ContactPerson] {
        var list: [ContactPerson] = []
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return list
        }
        for obj in arr {
            list.append(ContactPerson(
                name: str(obj, "name"),
                emailAddress: str(obj, "emailAddress"),
                displayName: str(obj, "displayName", str(obj, "name")),
                mailboxType: str(obj, "mailboxType", "Mailbox"),
                routingType: str(obj, "routingType", "SMTP")
            ))
        }
        return list
    }
}
