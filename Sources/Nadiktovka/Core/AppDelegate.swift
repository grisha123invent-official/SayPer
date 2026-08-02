import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private let hotkeys = HotkeyMonitor()
    private let indicator = RecordingIndicator()
    /// Создаётся по требованию. Жадная инициализация вешала запуск намертво:
    /// SettingsModel читает ключ из связки ключей, а на этот запрос система
    /// хочет показать диалог — которого до старта NSApplication показать негде.
    private lazy var settingsWindow = SettingsWindowController()
    /// Превращает события хоткея в команды записи — здесь живут режимы активации.
    private let gate = RecordingGate()
    private let statusMenu = StatusMenuBuilder()
    /// Панель вместо системного списка. Ленивая: ей нужен `self` как источник действий.
    private lazy var statusPanel = StatusPanelController(actions: self)

    private var lastText: String?
    private var isBusy = false
    private var transcription: Task<Void, Never>?
    private var elapsedTimer: Timer?

    /// Короче этого удержание считаем случайным.
    private let minimumDuration: TimeInterval = 0.35

    private enum Status {
        case idle
        case recording
        case transcribing
        case failed(String)
    }

    private var status: Status = .idle {
        didSet { renderStatusItem() }
    }

    // MARK: - Жизненный цикл

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.rotateIfNeeded()
        // Про ключ здесь намеренно молчим: любое обращение к связке ключей
        // на старте может заблокировать запуск ожиданием системного диалога.
        Log.write("--- Запуск. Универсальный доступ: \(HotkeyMonitor.isTrusted ? "выдан" : "НЕТ") "
                  + "| микрофон: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")

        // Без главного меню не работают ⌘C/⌘V в полях ввода: системные
        // сочетания правки доставляются именно через пункты меню.
        NSApp.mainMenu = buildMainMenu()

        // История и расходы слушают шину — оркестровка записи о них не знает.
        TranscriptionBus.register(HistoryStore.shared)
        TranscriptionBus.register(UsageStore.shared)

        statusMenu.actions = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        renderStatusItem()

        recorder.onLevel = { [weak self] level in
            self?.indicator.update(level: level)
        }

        gate.onCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .begin: self.beginRecording()
            case .finish: self.finishRecording()
            case .abort: self.abortRecording()
            }
        }

        hotkeys.onPress = { [weak self] in self?.gate.hotkeyPressed() }
        hotkeys.onRelease = { [weak self] in self?.gate.hotkeyReleased() }
        hotkeys.onCancel = { [weak self] in self?.gate.hotkeyCancelled() }
        hotkeys.onEscape = { [weak self] in
            guard let self else { return }
            // Шлюз забирает Esc себе только там, где сам держит запись.
            if !self.gate.escapePressed() {
                self.abortEverything()
            }
        }
        hotkeys.onSetupFailed = { [weak self] in
            self?.fail("нет доступа к клавиатуре — выдай «Универсальный доступ»")
        }
        hotkeys.onBecameActive = { [weak self] in
            guard let self else { return }
            self.status = .idle
            self.play("Glass")
            Log.write("Перехват заработал, готов к диктовке")
        }
        hotkeys.start()

        settingsWindow.model.onHotkeyChange = { [weak self] in
            self?.hotkeys.reload()
            self?.gate.reload()
        }

        // Пока в настройках записывают новое сочетание, глобальный перехват молчит.
        let center = NotificationCenter.default
        center.addObserver(forName: .hotkeyRecordingBegan, object: nil, queue: .main) { [weak self] _ in
            self?.hotkeys.suspend()
        }
        center.addObserver(forName: .hotkeyRecordingEnded, object: nil, queue: .main) { [weak self] _ in
            self?.hotkeys.resume()
        }

        Task { @MainActor in
            _ = await AudioRecorder.requestMicrophoneAccess()
            checkFirstRun()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.stopWatchdog()
        hotkeys.stop()
        recorder.cancel()
    }


    /// При первом запуске подсказываем, чего не хватает для работы.
    private func checkFirstRun() {
        if !HotkeyMonitor.isTrusted {
            requestKeyboardAccess()
            return
        }

        if Settings.shared.apiKey == nil {
            settingsWindow.show()
        }
    }

    // MARK: - Главное меню

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Скрыть", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let quitItem = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Пункты правки идут по цепочке респондеров — target намеренно nil.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Правка")
        editMenu.addItem(NSMenuItem(title: "Отменить", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Окно")
        windowMenu.addItem(NSMenuItem(title: "Закрыть", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        return mainMenu
    }

    // MARK: - Меню в строке статуса

    private func renderStatusItem() {
        guard let button = statusItem.button else { return }

        let symbol: String
        switch status {
        case .idle: symbol = "mic"
        case .recording: symbol = "mic.fill"
        case .transcribing: symbol = "waveform"
        case .failed: symbol = "exclamationmark.triangle"
        }

        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Надиктовка")
        button.image?.isTemplate = true
        button.contentTintColor = {
            switch status {
            case .recording: return .systemRed
            case .transcribing: return .systemBlue
            case .failed: return .systemOrange
            case .idle: return nil
            }
        }()

        statusMenu.lastText = lastText
        // Меню не вешаем на statusItem: клик открывает свою панель, иначе
        // системный список перехватит нажатие и панель не покажется.
        button.target = self
        button.action = #selector(toggleStatusPanel)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])

        statusPanel.refreshIfOpen()
    }

    /// Левый клик — панель, правый — короткое системное меню на случай,
    /// если панель почему-то не открылась (запасной путь к выходу).
    @objc private func toggleStatusPanel() {
        guard let button = statusItem.button else { return }

        if NSApp.currentEvent?.type == .rightMouseDown {
            statusPanel.close()
            statusItem.menu = statusMenu.build()
            button.performClick(nil)
            statusItem.menu = nil
            return
        }

        statusPanel.toggle(from: button)
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    /// Просит оба разрешения, нужных для перехвата клавиш, и открывает нужную панель.
    private func requestKeyboardAccess() {
        Log.write("Запрашиваю доступ к клавиатуре. Универсальный доступ: \(HotkeyMonitor.isTrusted) "
                  + "| мониторинг ввода: \(HotkeyMonitor.inputMonitoringStatus)")

        // Системные запросы сами добавляют приложение в нужные списки —
        // остаётся только включить переключатель.
        HotkeyMonitor.requestTrust()
        if !HotkeyMonitor.hasInputMonitoring {
            HotkeyMonitor.requestInputMonitoring()
        }

        let alert = NSAlert()
        alert.messageText = "Нужен доступ к клавиатуре"
        alert.informativeText = """
        Без него приложение не видит горячую клавишу и не может вставлять текст.

        Системные настройки → Конфиденциальность и безопасность → \
        Универсальный доступ → включи «Надиктовка».

        Если «Надиктовка» уже есть в списке, но не работает — удали её кнопкой «−», \
        затем добавь заново кнопкой «+» из папки «Программы».

        Перезапускать приложение не нужно: как только разрешение появится, \
        оно подхватится само и прозвучит сигнал.
        """
        alert.addButton(withTitle: "Открыть «Универсальный доступ»")
        alert.addButton(withTitle: "Открыть «Мониторинг ввода»")
        alert.addButton(withTitle: "Позже")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openPrivacyPane("Privacy_Accessibility")
        case .alertSecondButtonReturn:
            openPrivacyPane("Privacy_ListenEvent")
        default:
            break
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func showDiagnostics() {
        let micStatus: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micStatus = "разрешён"
        case .denied: micStatus = "ЗАПРЕЩЁН"
        case .restricted: micStatus = "ограничен системой"
        case .notDetermined: micStatus = "ещё не спрашивали"
        @unknown default: micStatus = "неизвестно"
        }

        let report = """
        Перехват клавиатуры: \(hotkeys.isActive ? "работает" : "НЕ РАБОТАЕТ")
        Универсальный доступ: \(HotkeyMonitor.isTrusted ? "выдан" : "НЕ ВЫДАН")
        Мониторинг ввода: \(HotkeyMonitor.inputMonitoringStatus)
        Микрофон: \(micStatus)
        API-ключ: \(Settings.shared.apiKey == nil ? "не задан" : "задан") · \(Keychain.backendDescription)
        Хоткей: \(Settings.shared.hotkey.displayString)
        Вставка: \(Settings.shared.insertMode.title)

        Путь: \(Bundle.main.bundlePath)
        Журнал: \(Log.fileURL.path)
        """

        Log.write("Диагностика:\n\(report)")

        let alert = NSAlert()
        alert.messageText = "Диагностика"
        alert.informativeText = report
        alert.addButton(withTitle: "Показать журнал")
        alert.addButton(withTitle: "Скопировать")
        alert.addButton(withTitle: "Закрыть")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
        case .alertSecondButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        default:
            break
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Запись

    private func beginRecording() {
        // Шлюз считает запись начатой, как только отдал команду. Если мы
        // выходим отсюда, не начав её, он обязан узнать об этом — иначе
        // в режиме «нажал-нажал» следующее нажатие будет принято за
        // завершение несуществующей записи, и фраза потеряется.
        guard !isBusy, !recorder.isRecording else {
            gate.recordingDidStop()
            return
        }

        guard Settings.shared.apiKey != nil else {
            gate.recordingDidStop()
            fail("не задан API-ключ")
            settingsWindow.show()
            return
        }

        do {
            try recorder.start()
            status = .recording
            indicator.setHint(gate.currentHint)
            indicator.show(.recording)
            play("Tink")
            Log.write("Запись пошла")
        } catch {
            gate.recordingDidStop()
            fail(error.localizedDescription)
        }
    }

    private func abortRecording() {
        guard recorder.isRecording else { return }
        recorder.cancel()
        gate.recordingDidStop()
        indicator.hide()
        status = .idle
    }

    private func finishRecording() {
        let stopped = recorder.stop()
        gate.recordingDidStop()
        guard let result = stopped else { return }

        guard result.duration >= minimumDuration else {
            Log.write("Запись отброшена: всего \(String(format: "%.2f", result.duration)) с")
            try? FileManager.default.removeItem(at: result.url)
            indicator.hide()
            status = .idle
            return
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: result.url.path)[.size] as? Int) ?? 0
        Log.write("Запись закончена: \(String(format: "%.2f", result.duration)) с, \(size) байт "
                  + "→ отправляю в \(Settings.shared.model.rawValue)")

        play("Pop")
        status = .transcribing
        indicator.show(.transcribing)
        isBusy = true
        startElapsedTimer()

        let startedAt = Date()
        transcription = Task { @MainActor in
            defer {
                isBusy = false
                stopElapsedTimer()
                transcription = nil
                try? FileManager.default.removeItem(at: result.url)
            }

            do {
                let text = try await Transcriber.transcribe(fileURL: result.url)
                guard !Task.isCancelled else { return }

                // Запись, остановленная авто-стопом, доставляется в буфер, а не
                // печатается: человек про неё забыл, и вслепую вставлять минуты
                // речи в случайное поле нельзя. Подмена одноразовая.
                let insertMode = gate.consumeInsertModeOverride() ?? Settings.shared.insertMode

                Log.write("Расшифровано \(text.count) символов, вставляю "
                          + "способом «\(insertMode.title)»")
                lastText = text
                indicator.hide()
                status = .idle
                TextInserter.deliver(text, mode: insertMode)
                play("Purr")

                TranscriptionBus.publish(TranscriptionRecord(
                    text: text,
                    audioDuration: result.duration,
                    latency: Date().timeIntervalSince(startedAt),
                    modelID: Settings.shared.model.rawValue,
                    language: Settings.shared.language,
                    cleanupUsed: Settings.shared.cleanup
                ))
            } catch {
                // Отмена приходит и как CancellationError, и как URLError(.cancelled) —
                // это не сбой, ругаться на неё не надо.
                let cancelled = error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                    || Task.isCancelled

                if cancelled {
                    Log.write("Расшифровка отменена")
                    indicator.hide()
                    status = .idle
                } else {
                    fail(error.localizedDescription)
                }
            }
        }
    }

    /// Esc: прерывает и запись, и ожидание ответа от OpenAI.
    private func abortEverything() {
        if recorder.isRecording {
            abortRecording()
            Log.write("Запись прервана по Esc")
            return
        }

        guard let transcription else { return }
        transcription.cancel()
        self.transcription = nil
        stopElapsedTimer()
        isBusy = false
        indicator.hide()
        status = .idle
        Log.write("Ожидание расшифровки прервано по Esc")
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        let startedAt = Date()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.indicator.update(elapsed: Date().timeIntervalSince(startedAt))
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    /// В пилюлю помещается несколько слов — длинный текст остаётся в меню и журнале.
    private func shortMessage(_ message: String) -> String {
        if message.contains("лимит времени") || message.lowercased().contains("timed out") {
            return "Сеть не ответила"
        }
        if message.contains("401") { return "Ключ не принят" }
        if message.contains("429") { return "Лимит запросов" }
        if message.contains("микрофон") { return "Нет микрофона" }
        if message.contains("клавиатуре") { return "Нет доступа" }
        if message.contains("пустой текст") { return "Не расслышал" }
        return message.count > 24 ? String(message.prefix(24)) + "…" : message
    }

    private func fail(_ message: String) {
        Log.write("ОШИБКА: \(message)")
        status = .failed(message)
        indicator.show(.error(shortMessage(message)))
        play("Basso")

        // Через несколько секунд возвращаем обычный вид иконки.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            if case .failed = self.status {
                self.status = .idle
            }
        }
    }

    private func play(_ name: String) {
        guard Settings.shared.playSounds else { return }
        NSSound(named: name)?.play()
    }
}

// MARK: - Меню в строке статуса

/// Реализация целиком, включая пункты, которых в меню пока нет: контракт
/// заморожен, чтобы слайс «Меню» верстал пункты, не возвращаясь сюда.
/// Панель просит у приложения ровно то же, что и меню, — отдельной реализации
/// не нужно, протоколы совпадают по составу.
extension AppDelegate: StatusPanelActions {}

extension AppDelegate: StatusMenuActions {
    var menuStatusTitle: String {
        switch status {
        case .idle: return "Готово · зажми \(Settings.shared.hotkey.displayString)"
        case .recording: return "Идёт запись…"
        case .transcribing: return "Расшифровка…"
        case .failed(let message): return "Ошибка: \(message)"
        }
    }

    var isHotkeyActive: Bool { hotkeys.isActive }

    var menuActivation: HotkeyActivation { gate.mode }

    func menuOpenSettings(_ section: SettingsSection) {
        settingsWindow.show(section)
    }

    func menuSetActivation(_ mode: HotkeyActivation) {
        Settings.shared.hotkeyActivation = mode
        // Шлюз — единственный, кто знает про режимы: он перечитывает настройку
        // и заодно сбрасывает состояние, чтобы смена на полуслове не залипла.
        gate.reload()
        indicator.setHint(gate.currentHint)
        renderStatusItem()
    }

    func menuCopy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func menuInsertAgain(_ text: String) {
        TextInserter.deliver(text, mode: Settings.shared.insertMode)
    }

    func menuShowDiagnostics() {
        showDiagnostics()
    }

    func menuRequestKeyboardAccess() {
        requestKeyboardAccess()
    }

    func menuToggleSounds() {
        Settings.shared.playSounds = !Settings.shared.playSounds
        settingsWindow.model.playSounds = Settings.shared.playSounds
        renderStatusItem()
    }

    func menuQuit() {
        NSApp.terminate(nil)
    }
}
