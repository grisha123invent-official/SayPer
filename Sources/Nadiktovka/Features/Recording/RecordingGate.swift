import Foundation

/// Как хоткей включает запись.
enum HotkeyActivation: String, CaseIterable, Identifiable {
    /// Держи клавишу и говори, отпустил — расшифровка.
    case hold
    /// Нажал — говоришь, нажал ещё раз — расшифровка.
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hold: return "Удержание"
        case .toggle: return "Нажал-нажал"
        }
    }

    var summary: String {
        switch self {
        case .hold: return "Держи клавишу и говори, отпустил — расшифровка"
        case .toggle: return "Нажал — говоришь, нажал ещё раз — расшифровка"
        }
    }
}

/// Шлюз между сырыми событиями хоткея и оркестровкой записи.
///
/// Существует, чтобы `AppDelegate` не знал про режимы активации: он получает
/// три понятные команды и выполняет их. Всё, что отличает «удержание» от
/// «нажал-нажал», живёт здесь и больше нигде.
///
/// Разница между режимами в одном: кто решает, что запись кончилась.
/// В удержании это палец на клавише — событий ровно столько, сколько нажатий,
/// и состояние держать не нужно. В «нажал-нажал» решает сам шлюз: между стартом
/// и финишем проходит сколько угодно времени и сколько угодно чужих событий,
/// поэтому `isRecording` здесь — не справка, а единственный источник правды.
/// Отсюда же авто-стоп: раз запись держит шлюз, он и обязан её закрыть, если
/// про неё забыли.
final class RecordingGate {
    enum Command {
        /// Начать запись.
        case begin
        /// Закончить запись и расшифровать.
        case finish
        /// Бросить запись без расшифровки.
        case abort
    }

    /// Команды приходят на том же потоке, на котором пришло событие хоткея
    /// (`HotkeyMonitor` уже увёл их на главный).
    var onCommand: ((Command) -> Void)?

    /// Подсказка для индикатора: чем режим отличается прямо сейчас.
    /// В режиме удержания подсказки нет — состояние очевидно из пальца на клавише.
    private(set) var currentHint: String?

    private(set) var mode: HotkeyActivation = .hold

    /// Считает ли шлюз, что запись сейчас идёт. В удержании это справочное
    /// значение, в «нажал-нажал» — основа всей логики.
    private(set) var isRecording = false

    /// Предел длины записи в «нажал-нажал», секунды.
    private var autoStopAfter: TimeInterval = Settings.shared.maxToggleDuration
    private var autoStopTimer: Timer?

    /// Слежение за настройками: режим меняют из двух мест — карточки «Режим»
    /// и пункта меню, — и оба просто пишут значение. Перезапрашивать его здесь
    /// дешевле, чем заводить каждому писателю канал до шлюза.
    private var settingsObserver: NSObjectProtocol?

    init() {
        reload()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.settingsDidChange()
        }
    }

    deinit {
        autoStopTimer?.invalidate()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    // MARK: - События хоткея

    func hotkeyPressed() {
        switch mode {
        case .hold:
            isRecording = true
            emit(.begin)
        case .toggle:
            // Первое нажатие начинает, второе заканчивает. Автоповтор сюда
            // не доходит: монитор шлёт событие только на смену состояния.
            if isRecording {
                isRecording = false
                emit(.finish)
            } else {
                isRecording = true
                emit(.begin)
            }
        }
    }

    func hotkeyReleased() {
        switch mode {
        case .hold:
            isRecording = false
            emit(.finish)
        case .toggle:
            // Между двумя нажатиями клавишу отпускают — это не событие.
            break
        }
    }

    /// Во время удержания нажали обычную клавишу — это шорткат, а не диктовка.
    func hotkeyCancelled() {
        switch mode {
        case .hold:
            isRecording = false
            emit(.abort)
        case .toggle:
            // Сюда попадаем, только если клавишу ещё держат с того самого
            // нажатия, что начало запись: значит человек набирает сочетание,
            // а не диктует. Записи от силы доля секунды — бросаем её.
            guard isRecording else { break }
            isRecording = false
            emit(.abort)
        }
    }

    /// Esc. `true` — шлюз обработал сам, `false` — пусть отменяет обычный путь
    /// (в удержании Esc прерывает и запись, и ожидание расшифровки).
    func escapePressed() -> Bool {
        switch mode {
        case .hold:
            return false
        case .toggle:
            // Запись, которую держит шлюз, никто, кроме него, не остановит —
            // забираем Esc себе. Ожидание расшифровки шлюза не касается:
            // там нечего держать, и обычный путь отменяет его сам.
            guard isRecording else { return false }
            isRecording = false
            emit(.abort)
            return true
        }
    }

    // MARK: - Обратная связь от записи

    /// Запись остановилась по любой причине, в том числе не по хоткею.
    func recordingDidStop() {
        isRecording = false
        stopAutoStop()
        updateHint()
    }

    /// Перечитать режим из настроек.
    ///
    /// Начатую запись здесь закрываем: после смены режима или сочетания события,
    /// которыми её собирались закончить, уже не придут — она осталась бы висеть.
    func reload() {
        let interrupted = isRecording

        mode = Settings.shared.hotkeyActivation
        autoStopAfter = Settings.shared.maxToggleDuration
        reset()

        if interrupted {
            Log.write("Настройки записи сменились на ходу — начатая запись отброшена")
            // Не через `emit`: состояние и таймер уже приведены в порядок `reset`.
            onCommand?(.abort)
        }
    }

    /// Забыть состояние, не выдавая команд.
    func reset() {
        isRecording = false
        stopAutoStop()
        updateHint()
    }

    // MARK: - Авто-стоп

    /// Страховка «нажал-нажал»: у записи, которую держит шлюз, нет естественного
    /// конца. Отвлёкся, свернул окно, забыл — и микрофон пишет часами, а платить
    /// за эти секунды потом по счёту. Поэтому не бросаем, а именно заканчиваем:
    /// сказанное всё-таки расшифруется, а не пропадёт.
    private func startAutoStop() {
        stopAutoStop()
        guard mode == .toggle, autoStopAfter > 0 else { return }

        let timer = Timer(timeInterval: autoStopAfter, repeats: false) { [weak self] _ in
            self?.autoStopFired()
        }
        // `.common`: иначе таймер замолкает, пока открыто меню или тянут окно.
        RunLoop.main.add(timer, forMode: .common)
        autoStopTimer = timer
    }

    private func stopAutoStop() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
    }

    private func autoStopFired() {
        guard isRecording else { return }
        isRecording = false
        Log.write("Авто-стоп: запись шла дольше \(Int(autoStopAfter)) с, заканчиваю сам")
        emit(.finish)
    }

    // MARK: -

    /// Настройки переписали — сверяемся. Режим сменился, значит запись надо
    /// перечитать целиком; сменился только предел авто-стопа — он применится
    /// к следующей записи, обрывать текущую из-за настройки незачем.
    private func settingsDidChange() {
        autoStopAfter = Settings.shared.maxToggleDuration
        guard Settings.shared.hotkeyActivation != mode else { return }
        reload()
    }

    private func updateHint() {
        switch mode {
        case .hold:
            currentHint = nil
        case .toggle:
            currentHint = isRecording ? "Нажми ещё раз" : nil
        }
    }

    private func emit(_ command: Command) {
        switch command {
        case .begin: startAutoStop()
        case .finish, .abort: stopAutoStop()
        }

        updateHint()
        onCommand?(command)
    }
}
