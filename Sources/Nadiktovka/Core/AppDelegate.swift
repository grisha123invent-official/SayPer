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
    /// Живёт только на время первого запуска, потом обнуляется.
    private var onboarding: OnboardingWindowController?

    private var lastText: String?
    /// Расшифровки идут параллельно: записав фразу, человек сразу диктует
    /// следующую, а ответы вставляются в порядке записей.
    private let queue = TranscriptionQueue()
    /// Громкость для значка в строке меню. Отдельно от индикатора: там кадры
    /// идут по тридцать раз в секунду, а значок перерисовывается вчетверо реже —
    /// в строке меню такой частоты глазу хватает, а работы вчетверо меньше.
    private var statusLevel: Float = 0
    private var lastStatusLevelDraw = Date.distantPast
    private var elapsedTimer: Timer?
    /// Устройство под текущую запись, если его назначило сочетание клавиш.
    private var deviceForNextRecording: String?

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

        // Тема применяется до создания окон: иначе первое окно успеет
        // отрисоваться системной темой и мигнёт при переключении.
        Settings.shared.appearanceMode.apply()

        // Без главного меню не работают ⌘C/⌘V в полях ввода: системные
        // сочетания правки доставляются именно через пункты меню.
        NSApp.mainMenu = buildMainMenu()

        // История и расходы слушают шину — оркестровка записи о них не знает.
        TranscriptionBus.register(HistoryStore.shared)
        TranscriptionBus.register(UsageStore.shared)

        statusMenu.actions = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        renderStatusItem()

        // Устройства переключились посреди записи: дописываем и отправляем то,
        // что успели, вместо того чтобы молча писать в мёртвый отвод.
        recorder.onDevicesChanged = { [weak self] in
            self?.finishRecording(devicesChanged: true)
        }

        recorder.onLevel = { [weak self] level in
            guard let self else { return }
            self.indicator.update(level: level)
            self.updateStatusLevel(level)
        }

        gate.onCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .begin: self.beginRecording()
            case .finish: self.finishRecording()
            case .abort: self.abortRecording()
            }
        }

        recoverUnfinished()

        queue.onReady = { [weak self] text, job in self?.deliver(text, from: job) }
        queue.onFailure = { [weak self] message in self?.fail(message) }
        queue.onProgress = { [weak self] items in
            self?.statusPanel.updatePending(items)
        }
        queue.onActivityChange = { [weak self] busy in
            guard let self else { return }
            if busy {
                self.status = .transcribing
                self.indicator.show(.transcribing)
                self.startElapsedTimer()
            } else {
                self.stopElapsedTimer()
                // Пилюлю прячем только если сейчас не идёт новая запись:
                // человек мог начать диктовать, пока хвост очереди дошивался.
                if !self.recorder.isRecording {
                    self.indicator.hide()
                    self.status = .idle
                }
            }
        }

        hotkeys.onPress = { [weak self] deviceTag in
            guard let self else { return }
            // Тег приходит только в режиме «клавиша на устройство».
            self.deviceForNextRecording = deviceTag
            self.gate.hotkeyPressed()
        }
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
            Sounds.play(.done)
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
        // Диагностику зовут из раздела «Ключ и доступ»: сам раздел про
        // AppDelegate ничего не знает и знать не должен.
        center.addObserver(forName: .showDiagnostics, object: nil, queue: .main) { [weak self] _ in
            self?.showDiagnostics()
        }

        Task { @MainActor in
            // Микрофон на старте спрашиваем только у тех, кто мастер уже прошёл.
            // Иначе первое, что видит человек, — голый системный алерт без
            // единого слова о том, что это за программа и зачем ей микрофон.
            guard Settings.shared.onboardingCompleted else {
                showOnboarding()
                return
            }
            _ = await AudioRecorder.requestMicrophoneAccess()
            checkFirstRun()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        OutputDucker.restore()
        hotkeys.stopWatchdog()
        hotkeys.stop()
        recorder.cancel()
    }


    /// Перерисовка значка под громкость — не чаще восьми раз в секунду.
    private func updateStatusLevel(_ level: Float) {
        guard case .recording = status else { return }
        let now = Date()
        guard now.timeIntervalSince(lastStatusLevelDraw) > 0.12 else { return }
        lastStatusLevelDraw = now
        statusLevel = level
        renderStatusItem()
    }

    /// Первый запуск: мастер вместо череды системных алертов.
    @MainActor
    private func showOnboarding() {
        let controller = OnboardingWindowController()
        // Держим ссылку, пока окно живо: контроллер владеет моделью с таймером,
        // и без этого его выметет сборщик прямо на первом шаге.
        onboarding = controller
        controller.onFinish = { [weak self] in
            guard let self else { return }
            self.onboarding = nil
            // Разрешения могли появиться прямо в мастере — перехват поднимется
            // сам, но состояние в настройках надо перечитать.
            self.settingsWindow.model.refreshPermissions()
        }
        controller.show()
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

        // Свой знак вместо системного микрофона: в строке меню у соседей
        // тоже микрофоны и волны, приложение должно узнаваться.
        switch status {
        case .idle: button.image = StatusItemIcon.idle()
        case .recording: button.image = StatusItemIcon.recording(level: statusLevel)
        case .transcribing: button.image = StatusItemIcon.transcribing()
        case .failed: button.image = StatusItemIcon.idle()
        }
        button.image?.accessibilityDescription = "SayPer"

        // Подкраску не ставим вообще. `contentTintColor` ломал шаблонную
        // отрисовку: во время записи глиф становился чёрным и на тёмной
        // строке меню пропадал. Цвет тут и не нужен — состояние видно
        // по форме: штрихи знака растут с голосом, при расшифровке стоят
        // вровень, а про ошибку подробно говорит пилюля.
        button.contentTintColor = nil

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
        Универсальный доступ → включи «SayPer».

        Если «SayPer» уже есть в списке, но не работает — удали её кнопкой «−», \
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
        Версия: \(AppInfo.versionLine)

        Перехват клавиатуры: \(hotkeys.isActive ? "работает" : "НЕ РАБОТАЕТ")
        Универсальный доступ: \(HotkeyMonitor.isTrusted ? "выдан" : "НЕ ВЫДАН")
        Мониторинг ввода: \(HotkeyMonitor.inputMonitoringStatus)
        Микрофон: \(micStatus)
        Устройство записи: \(AudioDevices.explain())
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
        // Ждать конца прошлой расшифровки больше не нужно: она доедет сама,
        // в фоне. Занят бывает только микрофон — он один.
        guard !recorder.isRecording else {
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
            try recorder.start(deviceTag: deviceForNextRecording)
            // Музыка и видео лезут в микрофон, поэтому глушим их на время
            // записи. Возврат — в каждой точке выхода из неё.
            OutputDucker.duck()
            status = .recording
            indicator.setHint(gate.currentHint)
            indicator.show(.recording)
            Sounds.play(.start)
            Log.write("Запись пошла")
        } catch {
            gate.recordingDidStop()
            fail(error.localizedDescription)
        }
    }

    private func abortRecording() {
        guard recorder.isRecording else { return }
        OutputDucker.restore()
        recorder.cancel()
        gate.recordingDidStop()
        indicator.hide()
        status = .idle
    }

    private func finishRecording(devicesChanged: Bool = false) {
        // Звук возвращаем сразу после остановки записи: пока идёт расшифровка,
        // микрофон уже не слушает и глушить нечего.
        OutputDucker.restore()

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

        Sounds.play(.stop)

        // Запись, остановленная авто-стопом, доставляется в буфер, а не
        // печатается: человек про неё забыл, и вслепую вставлять минуты речи
        // в случайное поле нельзя. Подмена одноразовая, поэтому способ вставки
        // запоминается здесь, а не в момент ответа: к тому времени очередь
        // может уже принять следующую фразу с обычным способом.
        let insertMode = gate.consumeInsertModeOverride() ?? Settings.shared.insertMode
        queue.enqueue(audio: result.url, duration: result.duration, insertMode: insertMode)

        // Предупреждение показываем последним — постановка в очередь тут же
        // выводит на пилюлю «расшифровываю», и сказанное раньше стёрлось бы,
        // не успев прочитаться. Молчать здесь нельзя: человек решит, что это
        // расшифровка плохая, а не запись оборвалась.
        if devicesChanged {
            indicator.show(.error("Устройство переключилось, записал "
                                  + "\(Int(result.duration)) с"))
        }
    }

    /// Готовый текст пришёл и дождался своей очереди.
    /// Подбирает записи, оставшиеся от прошлого запуска.
    ///
    /// Всё, что лежит в кладовке к моменту старта, недоставлено: удачная
    /// расшифровка убирает файл за собой. Обычно это одна фраза — та,
    /// на которой приложение перезапустилось.
    ///
    /// Ждать нажатия не стали намеренно: человек сказал фразу вслух и уже
    /// забыл про неё, а строка «нажми, чтобы дошифровать» так и осталась бы
    /// незамеченной. Дошифровываем сами и кладём в историю — оттуда он
    /// возьмёт текст, когда хватится.
    private func recoverUnfinished() {
        let files = RecordingVault.orphans()
        guard !files.isEmpty else { return }

        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)

        for url in files {
            let created = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            // Недельной давности запись человеку уже не нужна, а платить
            // за неё он всё равно не подписывался.
            guard created > cutoff else {
                Log.write("Забытая запись старше недели удалена: \(url.lastPathComponent)")
                RecordingVault.discard(url)
                continue
            }

            RecordingVault.repairIfNeeded(url)
            let duration = RecordingVault.duration(of: url)
            // Пустышка в пару сотен байт — это нажатая и сразу отпущенная
            // клавиша, а не фраза.
            guard duration > 0.4 else {
                RecordingVault.discard(url)
                continue
            }

            Log.write("Подбираю незаконченную запись: \(url.lastPathComponent), "
                      + String(format: "%.1f", duration) + " с")
            queue.enqueue(audio: url, duration: duration,
                          insertMode: .clipboardOnly, isRecovered: true)
        }
    }

    func menuForgetPending(_ id: Int) {
        queue.forget(id)
    }

    private func deliver(_ text: String, from job: TranscriptionQueue.Job) {
        // Подобранное после перезапуска в поле не вставляем: с той диктовки
        // прошло неизвестно сколько, курсор давно в другом окне, и текст
        // въехал бы в чужой документ. Кладём в историю — оттуда человек
        // возьмёт его сам, когда увидит.
        if job.isRecovered {
            Log.write("Подобрана незаконченная запись: \(text.count) символов, "
                      + "кладу в историю")
            TranscriptionBus.publish(TranscriptionRecord(
                text: text,
                audioDuration: job.duration,
                latency: 0,
                modelID: Settings.shared.model.rawValue,
                language: Settings.shared.language,
                cleanupUsed: Settings.shared.cleanup
            ))
            indicator.show(.error("Запись после перезапуска — в истории"))
            return
        }

        Log.write("Расшифровано \(text.count) символов, вставляю "
                  + "способом «\(job.insertMode.title)»")
        lastText = text
        TextInserter.deliver(text, mode: job.insertMode)
        Sounds.play(.done)

        TranscriptionBus.publish(TranscriptionRecord(
            text: text,
            audioDuration: job.duration,
            latency: Date().timeIntervalSince(job.startedAt),
            modelID: Settings.shared.model.rawValue,
            language: Settings.shared.language,
            cleanupUsed: Settings.shared.cleanup
        ))
    }

    /// Esc: прерывает и запись, и ожидание ответа от OpenAI.
    private func abortEverything() {
        if recorder.isRecording {
            abortRecording()
            Log.write("Запись прервана по Esc")
            return
        }

        guard !queue.isEmpty else { return }
        queue.cancelAll()
        stopElapsedTimer()
        indicator.hide()
        status = .idle
        Log.write("Ожидание расшифровки прервано по Esc")
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Считаем по самой старой фразе в очереди: именно её ждут дольше
            // всех, и именно она задерживает вставку остальных.
            self.indicator.update(elapsed: self.queue.oldestWait)
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
        // Страховка: если запись оборвалась ошибкой, приглушение не должно
        // остаться висеть до перезапуска.
        OutputDucker.restore()
        Log.write("ОШИБКА: \(message)")
        status = .failed(message)
        indicator.show(.error(shortMessage(message)))
        Sounds.play(.error)

        // Через несколько секунд возвращаем обычный вид иконки.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            if case .failed = self.status {
                self.status = .idle
            }
        }
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
