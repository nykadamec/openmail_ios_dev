import Foundation
import Security

/// Small, single-purpose Keychain store for the openMail session bearer cookie.
final class KeychainStore {
    enum StoreError: Error {
        case keychain(OSStatus)
        case invalidValue
    }

    static let authService = "nykadamec.openmail.auth"
    private static let legacyAccount = "session_id"

    private let service: String
    private let account: String

    init(service: String = KeychainStore.authService, account: String = ServerProfile.defaultPublicProfile.id.uuidString) {
        self.service = service
        self.account = account
        // The old implementation used the literal cookie name as its
        // account.  Migrate only while opening the built-in public profile;
        // custom profiles must never inherit another profile's credential.
        if service == Self.authService, account == ServerProfile.defaultPublicProfile.id.uuidString {
            Self.migrateLegacyAccount(service: service, destinationAccount: account)
        }
    }

    private static func migrateLegacyAccount(service: String, destinationAccount: String) {
        let destinationQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: destinationAccount,
        ]
        // Do not replace an existing profile credential with legacy data.
        var existing: CFTypeRef?
        let destinationStatus = SecItemCopyMatching(
            destinationQuery.merging([kSecReturnData as String: true]) { _, new in new } as CFDictionary,
            &existing
        )
        guard destinationStatus == errSecItemNotFound else { return }

        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(legacyQuery as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, !data.isEmpty else { return }

        var destination = destinationQuery
        destination[kSecValueData as String] = data
        destination[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        // Delete the legacy item only after the new item was successfully saved.
        guard SecItemAdd(destination as CFDictionary, nil) == errSecSuccess else { return }
        _ = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount,
        ] as CFDictionary)
    }

    func save(_ value: String) throws {
        guard let data = value.data(using: .utf8), !data.isEmpty else {
            throw StoreError.invalidValue
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Replacing the item instead of updating it also handles legacy items
        // whose accessibility attribute cannot be changed by SecItemUpdate.
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw StoreError.keychain(deleteStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
    }

    func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidValue
        }
        return value
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }
}
