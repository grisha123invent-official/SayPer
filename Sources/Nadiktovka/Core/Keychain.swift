import Foundation
import Security

/// Хранилище API-ключа. В UserDefaults ключ не попадает никогда.
///
/// Почему не обычная связка ключей. Классический keychain хранит рядом с записью
/// список доверенных программ, и запись в этом списке — снимок конкретной сборки.
/// Приложение пересобирается, снимок перестаёт совпадать, и система на каждое
/// чтение показывает «SayPer wants to access key… enter the login keychain
/// password». Кнопка «Always Allow» помогает ровно до следующей сборки.
///
/// Поэтому порядок такой:
/// 1. современная связка ключей (data protection) — там списка доверия нет,
///    доступ определяется подписью, диалог не появляется;
/// 2. если система её не даёт (для неё нужен entitlement, которого у локально
///    подписанного приложения может не быть) — файл с правами 0600.
/// Ключ из старой связки переносится в новое хранилище при первом чтении.
enum Keychain {
    private static let service = "com.grisha.nadiktovka"
    private static let account = "openai-api-key"

    /// Куда в итоге легло значение — видно в «Диагностике».
    private(set) static var backendDescription = "ещё не обращались"

    // MARK: - Чтение

    static func readAPIKey() -> String? {
        if let key = readModern() {
            backendDescription = "связка ключей (современная)"
            return key
        }

        if let key = readFile() {
            backendDescription = "файл с правами 0600"
            return key
        }

        // Ключ мог остаться от прежних версий в старой связке. Забираем его
        // оттуда один раз: это единственное место, где диалог ещё возможен.
        if let key = readLegacy() {
            Log.write("Ключ найден в старой связке ключей, переношу в новое хранилище")
            writeAPIKey(key)
            deleteLegacy()
            return key
        }

        return nil
    }

    // MARK: - Запись

    @discardableResult
    static func writeAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            deleteModern()
            deleteFile()
            deleteLegacy()
            return true
        }

        if writeModern(trimmed) {
            backendDescription = "связка ключей (современная)"
            deleteFile()
            return true
        }

        let saved = writeFile(trimmed)
        backendDescription = saved ? "файл с правами 0600" : "сохранить не удалось"
        return saved
    }

    // MARK: - Современная связка ключей

    private static func modernQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private static func readModern() -> String? {
        var query = modernQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    private static func writeModern(_ key: String) -> Bool {
        SecItemDelete(modernQuery() as CFDictionary)

        var attrs = modernQuery()
        attrs[kSecValueData as String] = Data(key.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess {
            // -34018 означает отсутствие нужного entitlement: у локально
            // подписанного приложения это норма, уходим в файл.
            Log.write("Современная связка ключей недоступна (\(status)), сохраняю в файл")
        }
        return status == errSecSuccess
    }

    private static func deleteModern() {
        SecItemDelete(modernQuery() as CFDictionary)
    }

    // MARK: - Файл с правами 0600

    private static var fileURL: URL {
        AppPaths.supportFile("openai-key")
    }

    private static func readFile() -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let key = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private static func writeFile(_ key: String) -> Bool {
        let url = fileURL
        do {
            try Data(key.utf8).write(to: url, options: [.atomic])
            // Права выставляем после каждой записи: атомарная запись подменяет
            // файл целиком и прав предыдущего не наследует.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            Log.write("Не удалось сохранить ключ в файл: \(error.localizedDescription)")
            return false
        }
    }

    private static func deleteFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Старая связка ключей (только чтение и удаление)

    private static func legacyQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readLegacy() -> String? {
        var query = legacyQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    private static func deleteLegacy() {
        SecItemDelete(legacyQuery() as CFDictionary)
    }
}
