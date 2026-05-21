import Foundation
import Security

enum KeychainHelper {
    static let service = "app.tunapop.token"

    enum Failure: Error {
        case unhandled(OSStatus)
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
                throw Failure.unhandled(addStatus)
            }
        } else if status != errSecSuccess {
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
            throw Failure.unhandled(status)
        }
    }
}
