import Foundation

final class ExchangeApiClient: NSObject {

    struct AttachmentFile {
        var name: String
        var data: Data
        var contentType: String
    }

    struct LoginResult {
        var canary: String
        var mailbox: String
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
        super.init()
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
    func login(login: String, password: String) async throws -> LoginResult {
        let base = session.serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let host = URL(string: base)?.host else { throw ApiError.invalidUrl }

        guard let url = URL(string: base + "/owa/auth.owa") else { throw ApiError.invalidUrl }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let dest = "https://\(host)/owa/"
        let parts: [String] = [
            "destination=" + urlEncode(dest),
            "flags=0",
            "forcedownlevel=0",
            "trusted=0",
            "username=" + urlEncode(login),
            "password=" + urlEncode(password),
            "isUtf8=1"
        ]
        req.httpBody = parts.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await urlSession.data(for: req)
        let http = response as? HTTPURLResponse
        let finalUrl = (http?.url?.absoluteString ?? "").lowercased()
        let html = String(data: data, encoding: .utf8) ?? ""

        if finalUrl.contains("logon.aspx") || finalUrl.contains("reason=2") || finalUrl.contains("reason=1") {
            throw ApiError.loginFailed
        }

        // Determine mailbox
        var mailbox = login
        if let parsed = parseMailbox(from: html) {
            mailbox = parsed
        } else if let owaUrl = URL(string: base + "/owa/"),
                  let (pageData, _) = try? await urlSession.data(from: owaUrl),
                  let pageHtml = String(data: pageData, encoding: .utf8),
                  let parsed = parseMailbox(from: pageHtml) {
            mailbox = parsed
        }

        let canary = canaryValue()
        if canary.isEmpty {
            throw ApiError.loginFailed
        }
        return LoginResult(canary: canary, mailbox: mailbox)
    }

    private func parseMailbox(from html: String) -> String? {
        let patterns = [
            "<meta[^>]*name=[\"']owa_mailbox[\"'][^>]*content=[\"']([^\"']+)[\"']",
            "name=[\"']owa_mailbox[\"'][^>]*content=[\"']([^\"']+)[\"']",
            "\"mailbox\":\"([^\"@]+@[^\"]+)\""
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(html.startIndex..<html.endIndex, in: html)
                if let match = regex.firstMatch(in: html, options: [], range: range),
                   match.numberOfRanges > 1,
                   let r = Range(match.range(at: 1), in: html) {
                    return String(html[r])
                }
            }
        }
        return nil
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
        let loginName = AppSettings.shared.fullLogin
        let passwordValue = CredentialStore.shared.password
        if loginName.isEmpty || passwordValue.isEmpty { return false }
        _ = try? await self.login(login: loginName, password: passwordValue)
        return !canaryValue().isEmpty
    }

    // MARK: - JSON helpers

    private func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private func defaultHeader() -> [String: Any] {
        let sid: [String: Any] = [
            "__type": "ConnectingSID:#Exchange",
            "SmtpAddress": session.mailbox
        ]
        let header: [String: Any] = [
            "__type": "ExchangeImpersonation:#Exchange",
            "ConnectingSID": sid
        ]
        return header
    }

    private func itemShape() -> [String: Any] {
        let shape: [String: Any] = [
            "__type": "ItemResponseShape:#Exchange",
            "BaseShape": "AllProperties"
        ]
        return shape
    }

    // MARK: - Operations

    func findItems(folderId: String, maxCount: Int = 50, offset: Int = 0) async throws -> String {
        let paging: [String: Any] = [
            "__type": "IndexedPageView:#Exchange",
            "MaxEntriesReturned": maxCount,
            "Offset": offset,
            "BasePoint": "Beginning"
        ]
        let parentFolder: [String: Any] = [
            "__type": "DistinguishedFolderId:#Exchange",
            "Id": folderId
        ]
        let body: [String: Any] = [
            "__type": "FindItemRequest:#Exchange",
            "ItemShape": itemShape(),
            "ParentFolderIds": [parentFolder],
            "ViewFilter": "All",
            "Paging": paging,
            "SortOrder": "Descending",
            "Traversal": "Shallow"
        ]
        let request: [String: Any] = [
            "__type": "FindItemJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": body
        ]
        return try await execute("/owa/service.svc?action=FindItem", body: jsonString([request]))
    }

    func getMailItem(itemId: String) async throws -> String {
        let itemIdDict: [String: Any] = ["__type": "ItemId:#Exchange", "Id": itemId]
        let body: [String: Any] = [
            "__type": "GetItemRequest:#Exchange",
            "ItemShape": itemShape(),
            "ItemIds": [itemIdDict]
        ]
        let request: [String: Any] = [
            "__type": "GetItemJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": body
        ]
        return try await execute("/owa/service.svc?action=GetItem", body: jsonString([request]))
    }

    func markAsRead(itemId: String) async throws -> String {
        let fieldUri: [String: Any] = ["__type": "FieldURI:#Exchange", "FieldURI": "message:IsRead"]
        let message: [String: Any] = ["__type": "Message:#Exchange", "IsRead": true]
        let update: [String: Any] = [
            "__type": "SetItemField:#Exchange",
            "FieldURI": fieldUri,
            "Message": message
        ]
        let itemIdDict: [String: Any] = ["__type": "ItemId:#Exchange", "Id": itemId]
        let change: [String: Any] = [
            "__type": "ItemChange:#Exchange",
            "ItemId": itemIdDict,
            "Updates": [update]
        ]
        let body: [String: Any] = [
            "__type": "UpdateItemRequest:#Exchange",
            "ItemChanges": [change]
        ]
        let request: [String: Any] = [
            "__type": "UpdateItemJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": body
        ]
        return try await execute("/owa/service.svc?action=UpdateItem", body: jsonString([request]))
    }

    func moveToDeleted(itemId: String) async throws -> String {
        let itemIdDict: [String: Any] = ["__type": "ItemId:#Exchange", "Id": itemId]
        let toFolder: [String: Any] = ["__type": "DistinguishedFolderId:#Exchange", "Id": "deleteditems"]
        let body: [String: Any] = [
            "__type": "MoveItemRequest:#Exchange",
            "ItemIds": [itemIdDict],
            "ToFolderId": toFolder
        ]
        let request: [String: Any] = [
            "__type": "MoveItemJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": body
        ]
        return try await execute("/owa/service.svc?action=MoveItem", body: jsonString([request]))
    }

    func resolveNames(query: String) async throws -> String {
        let body: [String: Any] = [
            "__type": "ResolveNamesRequest:#Exchange",
            "ReturnFullContactData": true,
            "SearchScope": "ActiveDirectory",
            "UnresolvedEntry": query
        ]
        let request: [String: Any] = [
            "__type": "ResolveNamesJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": body
        ]
        return try await execute("/owa/service.svc?action=ResolveNames", body: jsonString([request]))
    }

    func findPeople(query: String) async throws -> String {
        let body: [String: Any] = [
            "__type": "FindPeopleRequest:#Exchange",
            "SearchPeopleSuggestionIndex": true,
            "Query": query
        ]
        let request: [String: Any] = [
            "__type": "FindPeopleJsonRequest:#Exchange",
            "Header": defaultHeader(),
            "Body": body
        ]
        return try await execute("/owa/service.svc?action=FindPeople", body: jsonString([request]))
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
            let dict: [String: Any] = [
                "__type": "EmailAddress:#Exchange",
                "Name": r.name,
                "Address": r.emailAddress,
                "MailboxType": r.mailboxType
            ]
            return dict
        }

        let bodyContent: [String: Any] = [
            "__type": "BodyContent:#Exchange",
            "ContentType": "HTML",
            "Content": body
        ]

        var message: [String: Any] = [
            "__type": "Message:#Exchange",
            "Subject": subject,
            "Body": bodyContent,
            "ToRecipients": toRecipients.map(recipientJson)
        ]
        if !ccRecipients.isEmpty { message["CcRecipients"] = ccRecipients.map(recipientJson) }
        if !bccRecipients.isEmpty { message["BccRecipients"] = bccRecipients.map(recipientJson) }
        if !attachments.isEmpty {
            let atts: [[String: Any]] = attachments.map { att -> [String: Any] in
                let d: [String: Any] = [
                    "__type": "FileAttachment:#Exchange",
                    "Name": att.name,
                    "ContentType": att.contentType,
                    "Content": att.data.base64EncodedString(),
                    "IsInline": false
                ]
                return d
            }
            message["Attachments"] = atts
        }

        let saveFolder: [String: Any] = ["__type": "DistinguishedFolderId:#Exchange", "Id": "sentitems"]
        let bodyJson: [String: Any] = [
            "__type": "CreateItemRequest:#Exchange",
            "Items": [message],
            "MessageDisposition": "SendAndSaveCopy",
            "SaveFolderId": saveFolder
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
            let attId: [String: Any] = [
                "__type": "AttachmentId:#Exchange",
                "Id": attachmentId,
                "RootItemId": itemId
            ]
            let body: [String: Any] = [
                "__type": "GetAttachmentRequest:#Exchange",
                "AttachmentIds": [attId]
            ]
            let request: [String: Any] = [
                "__type": "GetAttachmentJsonRequest:#Exchange",
                "Header": defaultHeader(),
                "Body": body
            ]
            let json = try await execute("/owa/service.svc?action=GetAttachment", body: jsonString([request]))
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

extension ExchangeApiClient: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        ExchangeApiClient.respond(to: challenge, completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        ExchangeApiClient.respond(to: challenge, completionHandler)
    }

    static let corporateCABase64 = "MIIDCTCCAfGgAwIBAgIQbRE17NFuqa5NQf/yqukOYzANBgkqhkiG9w0BAQ0FADAXMRUwEwYDVQQDEwxEQzEtQUxBLTAtQ0EwHhcNMTYwODMwMTAxOTAzWhcNNDYwODMwMTAyOTAzWjAXMRUwEwYDVQQDEwxEQzEtQUxBLTAtQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCoa7pd4iz32vHTjFwPEokc9R30Ig5QDxvCtSHUVLikCs4b2yYcGpNSE9fxYuTeOND+yZaqpXZ8inWNjJxVXGqA7YegH8glDES9Blp9FpNBBBw7GPLrE1Pk1D/eYwIN7AZ9CefDTbp6elMPxEkEDrO1PyTaudVG37wh/O1Y231g8G3Nzrk5dqjGGZ1d61ayckwDGfZycKhZP3FDHzDfJ6EnuV1VY5Go8IjShVn+Cpt13kLhxf1/pTi7GfW07APzLcOimvglws5MLxCFadWIb4DEFfb1FHhxoNjGUF3ETZp0rPS3oeoaV9jv40xOCkXNC3KJUYSApvGN//yEgJKpMChtAgMBAAGjUTBPMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTNMsG+WfbjbpDa7cIQT9qMHtKzMzAQBgkrBgEEAYI3FQEEAwIBADANBgkqhkiG9w0BAQ0FAAOCAQEAjldpyPgPXsxHFb31OmzwJhwc5XQ1rMQpwyU+v4AMbCfTaIHS3awSHMcA+53rEv2qOjgzbMmeZ5KKeLGnTV55XIqT4pqXB2/r4FUfSrrMOTdZkbHnKXgZ+sCRtPoejET0WSWfeyzOzVnABCjnnNQhW3UfapEuRUYq8ellqznW5NY5MoZRYLgKC9qWn903TjawS6skEKXG6aix0AH2BYcq2F2b/sRJE9EfVsf6uFE7ZsRwhlOP+qPmxUASNNoumP4yVDhYJyCrtKhbst3n46v4/jSIaIaqxggvrO2QLegdZmZUoG7c85LUnKUQ1WbBCB+vw+BRGweN1mTvNNE1D8gVPA=="

    static func trustAnchors() -> [SecCertificate] {
        guard let data = Data(base64Encoded: corporateCABase64),
              let cert = SecCertificateCreateWithData(nil, data as CFData) else {
            return []
        }
        return [cert]
    }

    static var lastChallengeMethod = "-"
    static var lastTrustOK = false
    static var lastTrustError = "-"

    static func respond(
        to challenge: URLAuthenticationChallenge,
        _ completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        lastChallengeMethod = challenge.protectionSpace.authenticationMethod
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            let anchors = trustAnchors()
            if !anchors.isEmpty {
                SecTrustSetAnchorCertificates(trust, anchors as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, true)
            }
            var err: CFError?
            lastTrustOK = SecTrustEvaluateWithError(trust, &err)
            lastTrustError = err.map { ($0 as Error).localizedDescription } ?? "-"
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
