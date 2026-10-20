import Foundation
import Security

enum Keychain {
    private static let service = "com.prashant.wisprlite"

    private static func base(_ p: Provider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: p.keychainAccount]
    }

    /// The provider's environment variable first (handy for development and tests), then the Keychain.
    static func load(_ p: Provider) -> String? {
        if let env = ProcessInfo.processInfo.environment[p.envVar], !env.isEmpty { return env }
        return loadStored(p)
    }

    /// The Keychain item only, ignoring the environment variable.
    static func loadStored(_ p: Provider) -> String? {
        var query = base(p)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ p: Provider, _ key: String) -> Bool {
        SecItemDelete(base(p) as CFDictionary)
        var add = base(p)
        add[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ p: Provider) {
        SecItemDelete(base(p) as CFDictionary)
    }
}
