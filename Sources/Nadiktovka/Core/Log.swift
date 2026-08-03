import Foundation

/// Пишет события в ~/Library/Logs/SayPer.log — чтобы можно было понять,
/// на каком шаге всё встало, не запуская отладчик.
enum Log {
    /// Основное место — ~/Library/Logs. Если туда писать нельзя
    /// (бывает из-за защиты приватности), уходим во временную папку.
    static let fileURL: URL = {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/SayPer.log"),
            URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("SayPer.log")
        ]

        for url in candidates where isWritable(url) {
            return url
        }
        return candidates[1]
    }()

    private static func isWritable(_ url: URL) -> Bool {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            return manager.isWritableFile(atPath: url.path)
        }
        guard (try? Data().write(to: url)) != nil else { return false }
        return true
    }

    private static let queue = DispatchQueue(label: "com.grisha.nadiktovka.log")

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// Подробности для разбора: их пишем только когда включён подробный журнал.
    ///
    /// Разделение нужно, потому что обычный журнал читает человек — там должны
    /// быть события, а не поток. Подробный включают на время, чтобы поймать
    /// плавающую беду и отдать файл разработчику.
    static func debug(_ message: String) {
        guard Settings.shared.verboseLog else { return }
        write("· " + message)
    }

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"

        queue.async {
            guard let data = line.data(using: .utf8) else { return }

            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    /// Обрезает лог при старте, чтобы он не рос бесконечно.
    static func rotateIfNeeded() {
        queue.async {
            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                let size = attributes[.size] as? Int,
                size > 512_000
            else { return }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
