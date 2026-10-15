import Foundation
import Security

struct MailSession {
    var serverUrl: String = ""
    var mailbox: String = ""
    var domain: String = ""
    var displayName: String = ""
}

final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let serverUrl = "server_url"
        static let domain = "domain"
        static let mailbox = "mailbox"
        static let displayName = "display_name"
        static let notificationsEnabled = "notifications_enabled"
        static let showSubject = "show_subject"
        static let signature = "signature"
        static let fullLogin = "full_login"
    }

    var serverUrl: String {
        get { defaults.string(forKey: Keys.serverUrl) ?? "" }
        set { defaults.set(newValue, forKey: Keys.serverUrl) }
    }

    var domain: String {
        get { defaults.string(forKey: Keys.domain) ?? "" }
        set { defaults.set(newValue, forKey: Keys.domain) }
    }

    var mailbox: String {
        get { defaults.string(forKey: Keys.mailbox) ?? "" }
        set { defaults.set(newValue, forKey: Keys.mailbox) }
    }

    var displayName: String {
        get { defaults.string(forKey: Keys.displayName) ?? "" }
        set { defaults.set(newValue, forKey: Keys.displayName) }
    }

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.notificationsEnabled) }
    }

    var showSubjectInNotification: Bool {
        get { defaults.object(forKey: Keys.showSubject) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showSubject) }
    }

    var signature: String {
        get { defaults.string(forKey: Keys.signature) ?? "" }
        set { defaults.set(newValue, forKey: Keys.signature) }
    }

    var fullLogin: String {
        get { defaults.string(forKey: Keys.fullLogin) ?? "" }
        set { defaults.set(newValue, forKey: Keys.fullLogin) }
    }

    var isLoggedIn: Bool {
        !serverUrl.isEmpty && !mailbox.isEmpty
    }

    func currentSession() -> MailSession {
        MailSession(serverUrl: serverUrl, mailbox: mailbox, domain: domain, displayName: displayName)
    }

    func clearSession() {
        mailbox = ""
        displayName = ""
    }
}

final class CredentialStore {
    static let shared = CredentialStore()
    private let service = "com.crystalmail.ios.credentials"

    var password: String {
        get { Keychain.get(service: service, account: "password") ?? "" }
        set { Keychain.set(service: service, account: "password", value: newValue) }
    }
}

enum Keychain {
    static func set(service: String, account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
