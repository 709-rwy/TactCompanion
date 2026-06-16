import Foundation
import Security

enum TactCookieStore {
    private static let service = "jp.ac.thers.TACTCompanion"
    private static let account = "tact-session-cookies"

    static func save(_ cookies: [HTTPCookie]) {
        let properties = cookies.compactMap { cookie -> [String: Any]? in
            guard let values = cookie.properties else { return nil }
            return Dictionary(
                uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) }
            )
        }
        guard
            let data = try? PropertyListSerialization.data(
                fromPropertyList: properties,
                format: .binary,
                options: 0
            )
        else {
            return
        }

        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> [HTTPCookie] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let values = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [[String: Any]]
        else {
            return []
        }

        return values.compactMap { values in
            let properties = Dictionary(
                uniqueKeysWithValues: values.map {
                    (HTTPCookiePropertyKey(rawValue: $0.key), $0.value)
                }
            )
            return HTTPCookie(properties: properties)
        }
        .filter {
            $0.domain.contains("tact.ac.thers.ac.jp") &&
            ($0.expiresDate == nil || $0.expiresDate! > .now)
        }
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
