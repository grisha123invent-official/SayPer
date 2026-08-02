import AppKit
import Combine

/// Последние расшифровки. Заготовка: список живёт в памяти, на диск ничего
/// не пишется — хранение, поиск и переключатель «Хранить историю» добавляет
/// слайс «История». API заморожен: меню статус-бара верстается поверх него уже сейчас.
final class HistoryStore: ObservableObject, TranscriptionObserver {
    static let shared = HistoryStore()

    /// Сколько записей держим. Больше в меню и в списке всё равно не читают.
    static let limit = 20

    @Published private(set) var items: [TranscriptionRecord] = []

    var isEmpty: Bool { items.isEmpty }

    private init() {}

    // MARK: - Действия над записью

    func copy(_ record: TranscriptionRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)
    }

    func insertAgain(_ record: TranscriptionRecord) {
        TextInserter.deliver(record.text, mode: Settings.shared.insertMode)
    }

    func remove(_ record: TranscriptionRecord) {
        items.removeAll { $0.id == record.id }
    }

    func clear() {
        items.removeAll()
    }

    // MARK: - Подписка на шину

    func transcriptionDidFinish(_ record: TranscriptionRecord) {
        items.insert(record, at: 0)
        if items.count > Self.limit {
            items.removeLast(items.count - Self.limit)
        }
    }
}
