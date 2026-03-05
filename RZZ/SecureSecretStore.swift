import Foundation
import Security

enum SecureSecretStore {
    private static let service = "sivaz.RZZ.secure-secrets"

    static func readPassword(forAccount account: String) -> String? {
        var query = baseQuery(forAccount: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func savePassword(_ password: String, forAccount account: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        let query = baseQuery(forAccount: account)
        let updateAttrs: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }

        var addAttrs = query
        addAttrs[kSecValueData as String] = data
        #if os(iOS) || os(tvOS) || os(watchOS)
        addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif

        let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    static func deletePassword(forAccount account: String) {
        let query = baseQuery(forAccount: account)
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery(forAccount account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
