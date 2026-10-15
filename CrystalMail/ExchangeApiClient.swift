import Foundation

final class ExchangeApiClient: NSObject {

    struct AttachmentFile {
        var name: String
        var data: Data
        var contentType: String
    }

    enum ApiError: LocalizedError {
        case authRequired(String)
        case invalidUrl
        case loginFailed

        var errorDescription: String? {
            switch self {
            case .authRequired(let m): return m
            case .invalidUrl: return "Неверный адрес сервера"
            case .loginFailed: return "Не удалось войти. Проверьте логин/пароль"
            }
        }
    }

    private let session: MailSession
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(session: MailSession) {
        self.session = session
    }

    // MARK: - URL / cookies

    private func buildUrl(_ endpoint: String) -> String {
        let base = session.serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if endpoint.hasPrefix("http") { return endpoint }
        if endpoint.hasPrefix("/") { return base + endpoint }
        return base + "/" + endpoint
    }

    private func canaryValue() -> String {
        guard let url = URL(string: session.serverUrl) else { return "" }
        if let c = HTTPCookieStorage.shared.cookies(for: url)?.first(where: { $0.name == "X-OWA-CANARY" }) {
            return c.value
        }
        if let c = HTTPCookieStorage.shared.cookies?.first(where: { $0.name == "X-OWA-CANARY" }) {
            return c.value
        }
        return ""
    }

    // MARK: - Login

    @discardableResult
    func login(login: String, password: String) async throws -> String {
        let base = session.serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let host = URL(string: base)?.host else { throw ApiError.invalidUrl }

        let authUrl = base + "/auth.owa"
        guard let url = URL(string: authUrl) else { throw ApiError.invalidUrl }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let dest = "https://\(host)/owa/"
        let parts = [
            "destination=" + urlEncode(dest),
            "flags=0",
            "forcedownlevel=0",
            "trusted=0",
            "username=" + urlEncode(login),
            "password=" + urlEncode(password),
            "isUtf8=1"
        ]
        req.httpBody = parts.joined(separator: "&").data(using: .utf8)

        _ = try await urlSession.data(for: req)

        let canary = canaryValue()
        if canary.isEmpty {
            throw ApiError.loginFailed
        }
        return canary
    }

    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    // MARK: - Request building

    private func buildRequest(endpoint: String, body: String) -> URLRequest? {
        guard let url = URL(string: buildUrl(endpoint)) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let canary = canaryValue()
        if !canary.isEmpty { req.setValue(canary, forHTTPHeaderField: "X-OWA-CANARY") }
        if !body.isEmpty { req.httpBody = body.data(using: .utf8) }
        return req
    }

    private func execute(_ endpoint: String, body: String) async throws -> String {
        try await executeWithRelogin(endpoint: endpoint, body: body, retry: false)
    }

    private func executeWithRelogin(endpoint: String, body: String, retry: Bool) async throws -> String {
        guard let req = buildRequest(endpoint: endpoint, body: body) else {
            throw ApiError.invalidUrl
        }
        let (data, response) = try await urlSession.data(for: req)
        let text = String(data: data, encoding: .utf8) ?? ""
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let isHtml = contentType.contains("text/html") || trimmed.hasPrefix("<!DOCTYPE") || trimmed.hasPrefix("<html")

        if isHtml {
            let didRelogin = retry ? false : ((try? await relogin()) ?? false)
            if didRelogin {
                return try await executeWithRelogin(endpoint: endpoint, body: body, retry: true)
            }
            throw ApiError.authRequired("Сессия истекла — войдите заново")
        }

        if status == 302 || status == 401 || status == 440 {
            let didRelogin = retry ? false : ((try? await relogin()) ?? false)
            if didRelogin {
                return try await executeWithRelogin(endpoint: endpoint, body: body, retry: true)
            }
            throw ApiError.authRequired("Ошибка авторизации (\(status))")
        }

        return text
    }

    func relogin() async throws -> Bool {
        let login = AppSettings.shared.fullLogin
        let password = CredentialStore.shared.password
        if login.isEmpty || password.isEmpty { return false }
        _ = try? await login(login: login, password: password)
        return !canaryValue().isEmpty
    }

    // MARK: - JSON helpers

    private func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private func defaultHeader() -> [String: Any] {
        [
            "__type": "ExchangeImpersonation:#Exchange",
            "ConnectingSID": [
                "__type": "ConnectingSID:#Exchange",
                "SmtpAddress": session.mailbox
            ]
        ]
    }

    // MARK: - Operations

    func findItems(folderId: String, maxCount: Int = 50, offset: Int = 0) async throws -> String {
        let item: [String: Any] = [
            "__type": "FindItemJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": [
                "__type": "FindItemRequest:#Exchange",
                "ItemShape": [
                    "__type": "ItemResponseShape:#Exchange",
                    "BaseShape": "AllProperties"
                ],
                "ParentFolderIds": [
                    ["__type": "DistinguishedFolderId:#Exchange", "Id": folderId]
                ],
                "ViewFilter": "All",
                "Paging": [
                    "__type": "IndexedPageView:#Exchange",
                    "MaxEntriesReturned": maxCount,
                    "Offset": offset,
                    "BasePoint": "Beginning"
                ],
                "SortOrder": "Descending",
                "Traversal": "Shallow"
            ]
        ]
        return try await execute("/owa/service.svc?action=FindItem", body: jsonString([item]))
    }

    func getMailItem(itemId: String) async throws -> String {
        let item: [String: Any] = [
            "__type": "GetItemJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": [
                "__type": "GetItemRequest:#Exchange",
                "ItemShape": [
                    "__type": "ItemResponseShape:#Exchange",
                    "BaseShape": "AllProperties"
                ],
                "ItemIds": [
                    ["__type": "ItemId:#Exchange", "Id": itemId]
                ]
            ]
        ]
        return try await execute("/owa/service.svc?action=GetItem", body: jsonString([item]))
    }

    func markAsRead(itemId: String) async throws -> String {
        let item: [String: Any] = [
            "__type": "UpdateItemJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": [
                "__type": "UpdateItemRequest:#Exchange",
                "ItemChanges": [
                    [
                        "__type": "ItemChange:#Exchange",
                        "ItemId": ["__type": "ItemId:#Exchange", "Id": itemId],
                        "Updates": [
                            [
                                "__type": "SetItemField:#Exchange",
                                "FieldURI": ["__type": "FieldURI:#Exchange", "FieldURI": "message:IsRead"],
                                "Message": ["__type": "Message:#Exchange", "IsRead": true]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        return try await execute("/owa/service.svc?action=UpdateItem", body: jsonString([item]))
    }

    func moveToDeleted(itemId: String) async throws -> String {
        let item: [String: Any] = [
            "__type": "MoveItemJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": [
                "__type": "MoveItemRequest:#Exchange",
                "ItemIds": [
                    ["__type": "ItemId:#Exchange", "Id": itemId]
                ],
                "ToFolderId": ["__type": "DistinguishedFolderId:#Exchange", "Id": "deleteditems"]
            ]
        ]
        return try await execute("/owa/service.svc?action=MoveItem", body: jsonString([item]))
    }

    func resolveNames(query: String) async throws -> String {
        let item: [String: Any] = [
            "__type": "ResolveNamesJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": [
                "__type": "ResolveNamesRequest:#Exchange",
                "ReturnFullContactData": true,
                "SearchScope": "ActiveDirectory",
                "UnresolvedEntry": query
            ]
        ]
        return try await execute("/owa/service.svc?action=ResolveNames", body: jsonString([item]))
    }

    func findPeople(query: String) async throws -> String {
        let item: [String: Any] = [
            "__type": "FindPeopleJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": [
                "__type": "FindPeopleRequest:#Exchange",
                "SearchPeopleSuggestionIndex": true,
                "Query": query
            ]
        ]
        return try await execute("/owa/service.svc?action=FindPeople", body: jsonString([item]))
    }

    func sendMail(
        subject: String,
        body: String,
        toRecipients: [Recipient],
        ccRecipients: [Recipient] = [],
        bccRecipients: [Recipient] = [],
        attachments: [AttachmentFile] = []
    ) async throws -> String {

        func recipientJson(_ r: Recipient) -> [String: Any] {
            ["__type": "EmailAddress:#Exchange", "Name": r.name, "Address": r.emailAddress, "MailboxType": r.mailboxType]
        }

        var message: [String: Any] = [
            "__type": "Message:#Exchange",
            "Subject": subject,
            "Body": [
                "__type": "BodyContent:#Exchange",
                "ContentType": "HTML",
                "Content": body
            ],
            "ToRecipients": toRecipients.map(recipientJson)
        ]
        if !ccRecipients.isEmpty { message["CcRecipients"] = ccRecipients.map(recipientJson) }
        if !bccRecipients.isEmpty { message["BccRecipients"] = bccRecipients.map(recipientJson) }
        if !attachments.isEmpty {
            message["Attachments"] = attachments.map { att -> [String: Any] in
                [
                    "__type": "FileAttachment:#Exchange",
                    "Name": att.name,
                    "ContentType": att.contentType,
                    "Content": att.data.base64EncodedString(),
                    "IsInline": false
                ]
            }
        }

        let bodyJson: [String: Any] = [
            "__type": "CreateItemRequest:#Exchange",
            "Items": [message],
            "MessageDisposition": "SendAndSaveCopy",
            "SaveFolderId": ["__type": "DistinguishedFolderId:#Exchange", "Id": "sentitems"]
        ]

        let full: [String: Any] = [
            "__type": "CreateItemJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": bodyJson
        ]
        return try await execute("/owa/service.svc?action=CreateItem", body: jsonString([full]))
    }

    func getAttachmentBytes(itemId: String, attachmentId: String) async -> Data? {
        do {
            let item: [String: Any] = [
                "__type": "GetAttachmentJsonRequest:#Exchange",
                "Header": defaultHeader(),
                "Body": [
                    "__type": "GetAttachmentRequest:#Exchange",
                    "AttachmentIds": [
                        [
                            "__type": "AttachmentId:#Exchange",
                            "Id": attachmentId,
                            "RootItemId": itemId
                        ]
                    ]
                ]
            ]
            let json = try await execute("/owa/service.svc?action=GetAttachment", body: jsonString([item]))
            guard let data = json.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let response = arr.first,
                  let bodyObj = response["Body"] as? [String: Any],
                  let attachments = bodyObj["Attachments"] as? [[String: Any]],
                  let att = attachments.first,
                  let content = att["Content"] as? String else {
                return nil
            }
            return Data(base64Encoded: content)
        } catch {
            return nil
        }
    }
}

extension ExchangeApiClient: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
