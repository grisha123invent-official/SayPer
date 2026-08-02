import AppKit
import Combine

/// Последние расшифровки: список в памяти плюс его отражение в `HistoryArchive`.
///
/// Правило одно — список в памяти всегда главный, диск идёт следом. Поэтому
/// каждое изменение проходит через `persist()`, а не через отдельные вызовы
/// архива по месту: иначе однажды появится путь, который меняет список
/// и забывает про файл.
///
/// API заморожен в подготовительном коммите: меню статус-бара верстается
/// поверх него.
final class HistoryStore: ObservableObject, TranscriptionObserver {
    static let shared = HistoryStore()

    /// Сколько записей держим. Значение живёт в настройках (`history.limit`),
    /// здесь — только имя, под которым его читают остальные.
    static var limit: Int { Settings.shared.historyLimit }

    @Published private(set) var items: [TranscriptionRecord] = []

    /// «Хранить историю». Выключение стирает архив немедленно: настройка,
    /// которая начинает действовать со следующей расшифровки, оставляла бы
    /// на диске уже записанные тексты — ровно то, от чего человек защищается.
    ///
    /// Список текущего сеанса при этом остаётся: он нужен меню, чтобы
    /// «Вставить снова» продолжало работать. На диск он больше не попадёт.
    @Published var isStoringEnabled: Bool {
        didSet {
            guard isStoringEnabled != oldValue else { return }
            Settings.shared.historyEnabled = isStoringEnabled

            if isStoringEnabled {
                persist()
            } else {
                HistoryArchive.delete()
            }
        }
    }

    var isEmpty: Bool { items.isEmpty }

    private init() {
        let settings = Settings.shared
        isStoringEnabled = settings.historyEnabled

        if isStoringEnabled {
            items = HistoryArchive.load(limit: settings.historyLimit)
        } else {
            // Настройку могли выключить в прошлом запуске уже после того,
            // как файл появился, — или он остался от версии без переключателя.
            HistoryArchive.delete()
        }
    }

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
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    // MARK: - Подписка на шину

    func transcriptionDidFinish(_ record: TranscriptionRecord) {
        items.insert(record, at: 0)

        let limit = Self.limit
        if items.count > limit {
            items.removeLast(items.count - limit)
        }

        persist()
    }

    // MARK: - Диск

    /// Единственная точка записи на диск.
    ///
    /// Пустой список удаляет файл, а не пишет в него `[]`: остаться должно
    /// «истории на диске нет», а не «есть файл истории, но он пустой».
    private func persist() {
        guard isStoringEnabled else { return }

        if items.isEmpty {
            HistoryArchive.delete()
        } else {
            HistoryArchive.save(items, limit: Self.limit)
        }
    }
}
