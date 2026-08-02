import Foundation

/// Единственное место, где приложение решает, куда класть свои файлы.
/// Журнал живёт отдельно (`Log.fileURL`) — он нужен даже тогда,
/// когда Application Support недоступна.
enum AppPaths {
    /// Имя папки до переименования приложения в SayPer. Данные переносятся
    /// один раз: там лежат ключ, история расшифровок и статистика.
    private static let legacyFolder = "Надиктовка"
    private static let folder = "SayPer"

    /// ~/Library/Application Support/SayPer. Папка создаётся при первом обращении.
    static let supportDirectory: URL = {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")

        let directory = base.appendingPathComponent(folder, isDirectory: true)
        let legacy = base.appendingPathComponent(legacyFolder, isDirectory: true)

        // Переносим, только если новой папки ещё нет: иначе свежие данные
        // рискуют быть затёртыми старыми.
        if !manager.fileExists(atPath: directory.path),
           manager.fileExists(atPath: legacy.path) {
            do {
                try manager.moveItem(at: legacy, to: directory)
                Log.write("Данные перенесены из «\(legacyFolder)» в «\(folder)»")
            } catch {
                Log.write("Не удалось перенести данные: \(error.localizedDescription)")
            }
        }

        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// Путь к файлу внутри папки поддержки. Сам файл не создаётся.
    static func supportFile(_ name: String) -> URL {
        supportDirectory.appendingPathComponent(name)
    }
}
