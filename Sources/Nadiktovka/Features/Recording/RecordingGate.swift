import Foundation

/// Как хоткей включает запись.
enum HotkeyActivation: String, CaseIterable, Identifiable {
    /// Держи клавишу и говори, отпустил — расшифровка.
    case hold
    /// Нажал — говоришь, нажал ещё раз — расшифровка. Включает слайс «Нажал-нажал».
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
/// три понятные команды и выполняет их. Сегодня реализовано только удержание —
/// ровно то поведение, что было до появления шлюза.
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

    init() {
        reload()
    }

    // MARK: - События хоткея

    func hotkeyPressed() {
        switch mode {
        case .hold:
            isRecording = true
            emit(.begin)
        case .toggle:
            // Слайс «Нажал-нажал»: первое нажатие начинает, второе заканчивает.
            break
        }
    }

    func hotkeyReleased() {
        switch mode {
        case .hold:
            isRecording = false
            emit(.finish)
        case .toggle:
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
            break
        }
    }

    /// Esc. `true` — шлюз обработал сам, `false` — пусть отменяет обычный путь
    /// (в удержании Esc прерывает и запись, и ожидание расшифровки).
    func escapePressed() -> Bool {
        switch mode {
        case .hold:
            return false
        case .toggle:
            return false
        }
    }

    // MARK: - Обратная связь от записи

    /// Запись остановилась по любой причине, в том числе не по хоткею.
    func recordingDidStop() {
        isRecording = false
        updateHint()
    }

    /// Перечитать режим из настроек.
    func reload() {
        // Слайс «Нажал-нажал» читает здесь `record.activation`.
        mode = .hold
        reset()
    }

    /// Забыть состояние, не выдавая команд.
    func reset() {
        isRecording = false
        updateHint()
    }

    // MARK: -

    private func updateHint() {
        switch mode {
        case .hold:
            currentHint = nil
        case .toggle:
            currentHint = isRecording ? "Нажми ещё раз" : nil
        }
    }

    private func emit(_ command: Command) {
        updateHint()
        onCommand?(command)
    }
}
