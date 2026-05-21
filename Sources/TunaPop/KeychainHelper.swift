import Foundation
import Security

enum KeychainHelper {
    static let service = "app.tunapop.token"

    enum Failure: Error {
        case unhandled(OSStatus)
    }

    private static func logError(status: OSStatus, action: String, account: String) {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
        Log.system.error("Keychain error during \(action) for \(account): status \(status) (\(message))")
    }

    static func set(_ value: String, forAccount account: String) throws {
        if value.isEmpty {
            try remove(forAccount: account)
            return
        }

        guard let data = value.data(using: .utf8) else {
            return
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData] = data
            let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logError(status: addStatus, action: "SecItemAdd", account: account)
                throw Failure.unhandled(addStatus)
            }
        } else if status != errSecSuccess {
            logError(status: status, action: "SecItemUpdate", account: account)
            throw Failure.unhandled(status)
        }
    }

    static func get(forAccount account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        if status != errSecSuccess && status != errSecItemNotFound {
            logError(status: status, action: "SecItemCopyMatching", account: account)
        }
        return nil
    }

    static func remove(forAccount account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logError(status: status, action: "SecItemDelete", account: account)
            throw Failure.unhandled(status)
        }
    }
}
