import AVFoundation
import Foundation

/// Кладовка записей: где лежит наговоренное, пока текст не доставлен.
///
/// Раньше файл писался во временную папку системы и удалялся сразу после
/// расшифровки. Пока всё идёт гладко, разницы нет, но стоит приложению
/// перезапуститься — и наговоренное исчезало вместе с ним: временную папку
/// система вправе чистить когда угодно, а следа о незаконченной работе
/// не оставалось вовсе.
///
/// Теперь запись живёт в своей папке и удаляется **только** после того, как
/// текст доехал. Всё, что осталось в папке к моменту запуска, — это работа,
/// оборванная прошлым разом: приложение подберёт её само.
enum RecordingVault {
    /// Папка записей. В Application Support, а не в Caches: содержимое
    /// Caches система вправе стереть в любой момент, а здесь лежит то,
    /// что человек уже произнёс вслух и потерять не согласен.
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("SayPer/Записи", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Файл для новой записи.
    ///
    /// Имя начинается со времени, чтобы подобранные после перезапуска
    /// фразы вставали в том же порядке, в каком были наговорены.
    static func newRecordingURL() -> URL {
        let stamp = ISO8601DateFormatter.filenameSafe.string(from: Date())
        return folder
            .appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("wav")
    }

    /// Записи, оставшиеся от прошлого запуска.
    ///
    /// Всё, что лежит в папке в момент старта, по определению недоставлено:
    /// удачная расшифровка убирает файл за собой.
    static func orphans() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "wav" }.sorted { $0.path < $1.path }
    }

    /// Длительность записи по самому файлу: описания рядом нет намеренно —
    /// лишний файл пришлось бы держать в согласии с основным, а звук
    /// и так знает про себя всё нужное.
    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else {
            return 0
        }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Починка оборванного файла

    /// Дописывает в заголовок настоящие размеры.
    ///
    /// WAV выбран для записи именно ради этого. У него данные идут сразу
    /// за коротким заголовком, поэтому файл, оборванный на полуслове, теряет
    /// только правильные числа в заголовке — сам звук на месте, и его хватает
    /// починить двумя числами. У m4a иначе: оглавление дописывается при
    /// закрытии файла, и убитая посреди фразы запись не открывается ничем.
    ///
    /// Ради размера отправки платить потерей записи не стоит: сжимаем
    /// уже перед отправкой, см. `compressed(_:)`.
    @discardableResult
    static func repairIfNeeded(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forUpdating: url) else { return false }
        defer { try? handle.close() }

        guard let total = try? handle.seekToEnd(), total > 44,
              let head = read(handle, at: 0, count: 12), head.count == 12,
              head.prefix(4) == Data("RIFF".utf8), head.suffix(4) == Data("WAVE".utf8)
        else { return false }

        // Идём по кускам файла до звуковых данных: между заголовком и ними
        // бывают служебные куски, и их длина заранее неизвестна.
        var offset: UInt64 = 12
        while offset + 8 <= total {
            guard let chunk = read(handle, at: offset, count: 8), chunk.count == 8 else { return false }
            let size = UInt32(littleEndian: chunk.suffix(4).withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self)
            })

            if chunk.prefix(4) == Data("data".utf8) {
                let actual = UInt32(total - (offset + 8))
                guard size != actual else { return false }   // файл закрыт правильно
                write32(handle, at: 4, UInt32(total - 8))
                write32(handle, at: offset + 4, actual)
                Log.write("Оборванная запись починена: в заголовке было \(size) байт, "
                          + "на деле \(actual)")
                return true
            }

            guard size > 0 else { return false }
            offset += 8 + UInt64(size) + UInt64(size % 2)
        }
        return false
    }

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) -> Data? {
        try? handle.seek(toOffset: offset)
        return try? handle.read(upToCount: count)
    }

    private static func write32(_ handle: FileHandle, at offset: UInt64, _ value: UInt32) {
        var little = value.littleEndian
        let data = Data(bytes: &little, count: 4)
        try? handle.seek(toOffset: offset)
        try? handle.write(contentsOf: data)
    }

    // MARK: - Сжатие перед отправкой

    /// Сжимает запись в m4a. Возвращает исходный файл, если не вышло:
    /// тяжёлая отправка лучше несостоявшейся.
    ///
    /// Те же тринадцать секунд речи весят около 40 КБ вместо 430 КБ,
    /// и отправка перестаёт упираться в таймаут на слабой сети.
    static func compressed(_ source: URL) -> URL {
        guard source.pathExtension == "wav" else { return source }

        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: target)

        let aac: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24_000
        ]

        do {
            let input = try AVAudioFile(forReading: source)
            let output = try AVAudioFile(forWriting: target, settings: aac)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat,
                                                frameCapacity: 8192) else { return source }

            while input.framePosition < input.length {
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }
            return target
        } catch {
            Log.write("Сжать запись не удалось (\(error.localizedDescription)), "
                      + "отправляю как есть")
            try? FileManager.default.removeItem(at: target)
            return source
        }
    }
}

private extension ISO8601DateFormatter {
    /// Время в имени файла: двоеточия в путях допустимы, но в Finder
    /// показываются косой чертой и путают.
    static let filenameSafe: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay,
                                   .withTime, .withDashSeparatorInDate]
        return formatter
    }()
}
