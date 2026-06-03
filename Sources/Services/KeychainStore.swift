import Foundation
import OSLog
import Security

protocol TokenStore {
    func token(for credential: SessionCredential) -> String?
    func setToken(_ token: String, for credential: SessionCredential)
    func deleteToken(for credential: SessionCredential)
}

/// Thin wrapper over the Security framework for storing Jellyfin access tokens.
///
/// Replaces Swiftfin's KeychainSwift dependency with direct `SecItem*` calls. Tokens are
/// stored as `kSecClassGenericPassword` items, accounted by `SessionCredential.account`
/// (`"<serverID>:<userID>"`), accessible after first unlock. No keychain access group is
/// used (keeps signing simple across platforms).
struct KeychainStore {
    private let service = "dev.ericslutz.gus.tokens"
    private let logger = Logger(category: .keychain)

    static let shared = KeychainStore()

    // MARK: - Read

    func token(for credential: SessionCredential) -> String? {
        token(account: credential.account)
    }

    func token(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("Keychain read failed: \(status, privacy: .public)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Write

    func setToken(_ token: String, for credential: SessionCredential) {
        setToken(token, account: credential.account)
    }

    func setToken(_ token: String, account: String) {
        let data = Data(token.utf8)
        let query = baseQuery(account: account)

        // Update if present, otherwise add.
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("Keychain add failed: \(addStatus, privacy: .public)")
            }
        } else if updateStatus != errSecSuccess {
            logger.error("Keychain update failed: \(updateStatus, privacy: .public)")
        }
    }

    // MARK: - Delete

    func deleteToken(for credential: SessionCredential) {
        deleteToken(account: credential.account)
    }

    func deleteToken(account: String) {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            logger.error("Keychain delete failed: \(status, privacy: .public)")
        }
    }

    // MARK: - Private

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

extension KeychainStore: TokenStore {}
