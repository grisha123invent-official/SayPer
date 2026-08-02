import Foundation

/// Архив истории на диске: `~/Library/Application Support/Надиктовка/history.json`.
///
/// Единственный файл в приложении, где лежат сами тексты расшифровок
/// (`AppEvents.swift`, договорённость про `UsageSample`). Поэтому им управляет
/// ровно один переключатель — «Хранить историю», и выключенный он означает,
/// что файла нет вообще, а не что в него перестали дописывать.
///
/// Запись синхронная и намеренно: файл маленький (двадцать записей — единицы
/// килобайт), а асинхронная очередь дала бы окно, в котором последняя
/// расшифровка теряется при выходе из приложения сразу после диктовки.
enum HistoryArchive {
    static var fileURL: URL { AppPaths.supportFile("history.json") }

    /// Даты — ISO 8601, а не `Double` от «эпохи Apple»: файл должен читаться
    /// будущими версиями и глазами, если понадобится разобраться руками.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Читает архив, отдаёт свежие записи первыми и не длиннее лимита.
    ///
    /// Битый или недоступный файл — это пустая история, а не падение при старте:
    /// история вспомогательна, ронять из-за неё приложение нельзя.
    static func load(limit: Int) -> [TranscriptionRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        guard let stored = try? decoder.decode([TranscriptionRecord].self, from: data) else {
            Log.write("История: архив не разобрался, начинаем с пустого списка")
            return []
        }

        // Файл мог остаться от версии, которая писала его с правами 0644.
        // Чинить такой архив надо при первом же чтении, а не ждать записи,
        // которой может и не случиться.
        restrictAccess()

        let ordered = stored.sorted { $0.date > $1.date }
        return Array(ordered.prefix(max(limit, 0)))
    }

    /// Перезаписывает архив последними `limit` записями.
    ///
    /// Ожидает список, уже упорядоченный свежими вперёд, — таким его держит
    /// `HistoryStore`, и пересортировывать его здесь значило бы дублировать
    /// правило хранения в двух местах.
    static func save(_ records: [TranscriptionRecord], limit: Int) {
        let slice = Array(records.prefix(max(limit, 0)))

        guard let data = try? encoder.encode(slice) else {
            Log.write("История: не удалось закодировать архив")
            return
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            restrictAccess()
        } catch {
            Log.write("История: не удалось записать архив — \(error.localizedDescription)")
        }
    }

    /// Права 0600: файл читает и пишет только владелец.
    ///
    /// Это единственное место в приложении, где тексты расшифровок лежат
    /// открытым JSON, а умолчание `Data.write` — 0644, то есть историю диктовок
    /// видит любой другой пользователь этого Mac. Права выставляются после
    /// каждой записи, а не однажды при создании: атомарная запись подменяет
    /// файл целиком и права прежнего не наследует.
    private static func restrictAccess() {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            Log.write("История: не удалось ограничить доступ к архиву — \(error.localizedDescription)")
        }
    }

    /// Убирает файл целиком. Вызывается, когда «Хранить историю» выключают
    /// и когда список опустел: пустой архив на диске — это всё ещё файл
    /// с историей, и объяснить человеку его существование нечем.
    static func delete() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return }

        do {
            try manager.removeItem(at: fileURL)
        } catch {
            Log.write("История: не удалось удалить архив — \(error.localizedDescription)")
        }
    }
}
