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

    /// Сколько ждать, пока прежняя программа реально выйдет на передний план.
    /// Меньше — и синтетический ⌘V застаёт ещё наше окно.
    private static let focusHandover: TimeInterval = 0.2

    /// Столько же ждёт `TextInserter`, прежде чем вернуть в буфер прежнее
    /// содержимое. Значение продублировано осознанно: `TextInserter` — чужой
    /// файл, и договорённость о задержке проще держать здесь комментарием,
    /// чем расширять его API ради одного числа.
    private static let pasteRestoreWindow: TimeInterval = 0.4

    @Published private(set) var items: [TranscriptionRecord] = []

    /// Короткое сообщение под списком. Заводится только на честную деградацию
    /// «вставить не вышло, текст в буфере»: молчаливый провал вставки выглядит
    /// как потерянное нажатие, а обещать вставку, которой не было, нельзя.
    @Published private(set) var notice: String?

    /// «Хранить историю». Выключение стирает архив немедленно: настройка,
    /// которая начинает действовать со следующей расшифровки, оставляла бы
    /// на диске уже записанные тексты — ровно то, от чего человек защищается.
    ///
    /// Список текущего сеанса при этом остаётся: он нужен меню, чтобы
    /// «Вставить снова» продолжало работать. На диск он больше не попадёт —
    /// ни сейчас, ни обратным включением переключателя.
    @Published var isStoringEnabled: Bool {
        didSet {
            guard isStoringEnabled != oldValue else { return }
            Settings.shared.historyEnabled = isStoringEnabled

            if isStoringEnabled {
                // Ничего не досыпаем: на диск поедет первая расшифровка после
                // включения. Всё, что накопилось при выключенном хранении,
                // помечено как «не для диска» и таким остаётся.
                persist()
            } else {
                // Файл стёрли по прямой просьбе. Вернуть его содержимое
                // обратным включением было бы неожиданностью, поэтому и то,
                // что было в списке до выключения, на диск больше не пойдёт.
                volatileIDs.formUnion(items.map(\.id))
                HistoryArchive.delete()
            }
        }
    }

    var isEmpty: Bool { items.isEmpty }

    /// Записи, которым на диск нельзя: появившиеся при выключенном хранении
    /// и те, что лежали в списке в момент выключения.
    private var volatileIDs: Set<UUID> = []

    /// Кто был на переднем плане до нас. Нужен «Вставить снова» из окна
    /// настроек: окно само фронтальное, и вставлять некуда, пока фокус наш.
    private var previousApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    /// До какого момента `TextInserter` ещё может вернуть в буфер прежнее
    /// содержимое. Всё, что мы кладём в буфер в этом окне, надо положить ещё раз.
    private var pasteRestoreDeadline: Date?

    /// Счётчик показов сообщения: гасит только своё, а не то, что успело
    /// появиться следом.
    private var noticeToken = 0

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

        watchFrontmostApp()
    }

    // MARK: - Действия над записью

    func copy(_ record: TranscriptionRecord) {
        Self.write(record.text)

        // Гонка за буфером: после «Вставить снова» `TextInserter` через 0.4 с
        // возвращает прежнее содержимое. Клик по строке, попавший в это окно,
        // иначе окажется стёрт — галочка «скопировано» горит, а в буфере чужое.
        guard let deadline = pasteRestoreDeadline, deadline > Date() else { return }
        let text = record.text
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline.timeIntervalSinceNow + 0.05) {
            Self.write(text)
        }
    }

    /// «Вставить снова».
    ///
    /// Из меню статус-бара приложение остаётся аксессуаром, фокус — у прежней
    /// программы, и текст едет прямо туда. Из окна настроек фронтальны мы сами
    /// (`SettingsWindowController.show()` делает `NSApp.activate`): синтетический
    /// ⌘V ушёл бы в наше же окно — в поле поиска, если фокус там, — а через 0.4 с
    /// буфер вернулся бы к прежнему содержимому, и нажатие пропало бы бесследно.
    ///
    /// Поэтому сначала отдаём передний план прежней программе и только потом
    /// доставляем текст. Если отдать некому или фокус не ушёл — честно
    /// оставляем текст в буфере и говорим об этом.
    func insertAgain(_ record: TranscriptionRecord) {
        let mode = Settings.shared.insertMode

        guard mode != .clipboardOnly, NSRunningApplication.current.isActive else {
            deliver(record, mode: mode)
            return
        }

        guard
            let target = previousApp,
            !target.isTerminated,
            target.activate(options: [.activateIgnoringOtherApps])
        else {
            fallBackToClipboard(record)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusHandover) { [weak self] in
            guard let self else { return }
            guard !NSRunningApplication.current.isActive else {
                self.fallBackToClipboard(record)
                return
            }
            self.deliver(record, mode: mode)
        }
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
        // При выключенном хранении запись живёт только этот сеанс: она нужна
        // меню и списку, но на диск не попадёт даже после включения.
        if !isStoringEnabled {
            volatileIDs.insert(record.id)
        }

        items.insert(record, at: 0)

        let limit = Self.limit
        if items.count > limit {
            items.removeLast(items.count - limit)
        }

        persist()
    }

    // MARK: - Доставка текста

    private func deliver(_ record: TranscriptionRecord, mode: InsertMode) {
        if mode == .paste {
            pasteRestoreDeadline = Date().addingTimeInterval(Self.pasteRestoreWindow)
        }
        TextInserter.deliver(record.text, mode: mode)
    }

    private func fallBackToClipboard(_ record: TranscriptionRecord) {
        Self.write(record.text)
        Log.write("История: некому отдать фокус, текст оставлен в буфере")
        show("Вставлять было некуда — текст скопирован в буфер")
    }

    private func show(_ text: String) {
        notice = text
        noticeToken += 1
        let token = noticeToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.noticeToken == token else { return }
            self.notice = nil
        }
    }

    private static func write(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Запоминает последнюю чужую программу на переднем плане.
    private func watchFrontmostApp() {
        let ourPID = NSRunningApplication.current.processIdentifier

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ourPID {
            previousApp = frontmost
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.processIdentifier != ourPID
            else { return }
            self?.previousApp = app
        }
    }

    // MARK: - Диск

    /// Единственная точка записи на диск.
    ///
    /// Пустой список удаляет файл, а не пишет в него `[]`: остаться должно
    /// «истории на диске нет», а не «есть файл истории, но он пустой».
    private func persist() {
        // Выпавшие из списка идентификаторы не копим.
        volatileIDs.formIntersection(items.map(\.id))

        guard isStoringEnabled else { return }

        let storable = items.filter { !volatileIDs.contains($0.id) }
        if storable.isEmpty {
            HistoryArchive.delete()
        } else {
            HistoryArchive.save(storable, limit: Self.limit)
        }
    }
}
