import Foundation
import Security

/// Хранилище API-ключа в Keychain. В UserDefaults ключ не попадает.
enum Keychain {
    private static let service = "com.grisha.nadiktovka"
    private static let account = "openai-api-key"

    static func readAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    /// Запись помнит, какая сборка её создала. После смены подписи старый
    /// список доверия перестаёт совпадать, и система спрашивает пароль при
    /// каждом чтении. Достаточно один раз переписать ключ уже из текущей
    /// сборки — доверие выпишется заново, и запросы прекратятся.
    static func refreshOwnership() {
        guard let key = readAPIKey() else { return }
        writeAPIKey(key)
        Log.write("Запись в связке ключей пересоздана под текущую подпись")
    }

    @discardableResult
    static func writeAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty else { return true }

        var attrs = base
        attrs[kSecValueData as String] = Data(trimmed.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }
}
