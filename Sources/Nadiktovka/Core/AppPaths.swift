import Foundation

/// Единственное место, где приложение решает, куда класть свои файлы.
/// Журнал живёт отдельно (`Log.fileURL`) — он нужен даже тогда,
/// когда Application Support недоступна.
enum AppPaths {
    /// ~/Library/Application Support/Надиктовка. Папка создаётся при первом обращении.
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")

        let directory = base.appendingPathComponent("Надиктовка", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// Путь к файлу внутри папки поддержки. Сам файл не создаётся.
    static func supportFile(_ name: String) -> URL {
        supportDirectory.appendingPathComponent(name)
    }
}
