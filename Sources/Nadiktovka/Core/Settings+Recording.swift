import Foundation

/// Через сколько «нажал-нажал» останавливает запись само.
///
/// Отдельный тип, а не голые секунды: варианты одни и те же в карточке и в шлюзе,
/// а хранить в настройках произвольное число незачем — из интерфейса его всё равно
/// не задать, зато чужое значение на диске сломало бы выбор в списке.
enum AutoStopLimit: TimeInterval, CaseIterable, Identifiable {
    case minute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case halfHour = 1800

    var id: TimeInterval { rawValue }

    var title: String {
        switch self {
        case .minute: return "1 минута"
        case .fiveMinutes: return "5 минут"
        case .tenMinutes: return "10 минут"
        case .halfHour: return "30 минут"
        }
    }
}

/// Настройки записи: префикс ключей `record.*`.
///
/// Значения по умолчанию задаются прямо здесь, в месте чтения — общий
/// `register(defaults:)` в `Settings` намеренно не расширяется.
extension Settings {
    private enum RecordingKey {
        /// Как хоткей включает запись: удержание или «нажал-нажал».
        static let activation = "record.activation"
        /// Предел длины записи в «нажал-нажал», секунды.
        static let maxToggleDuration = "record.maxToggleDuration"
    }

    /// Режим активации. Неизвестное значение считается отсутствующим: удержание —
    /// то поведение, к которому человек привык, и откатываться безопасно именно к нему.
    ///
    /// Пишут это свойство двое — карточка «Режим» и пункт меню. Читает
    /// `RecordingGate`, он же следит за изменением: перезапуск для смены режима
    /// не нужен. Ключ существует ровно здесь: писать `"record.activation"`
    /// строкой мимо этого свойства нельзя — переименование ключа тогда молча
    /// разведёт писателя и читателя.
    var hotkeyActivation: HotkeyActivation {
        get { HotkeyActivation(rawValue: text(RecordingKey.activation)) ?? .hold }
        set { set(newValue.rawValue, forKey: RecordingKey.activation) }
    }

    /// Через сколько «нажал-нажал» завершает запись само.
    ///
    /// Пять минут по умолчанию: диктовка длиннее — редкость, а вот забытая
    /// включённой запись держит микрофон и копит секунды, за которые потом платить.
    ///
    /// Своей строки в интерфейсе у предела нет: карточка «Режим» в утверждённом
    /// мокапе — это сегменты и одна строка описания. Это страховка, а не настройка.
    var autoStopLimit: AutoStopLimit {
        get {
            let stored = decimal(
                RecordingKey.maxToggleDuration,
                default: AutoStopLimit.fiveMinutes.rawValue
            )
            return AutoStopLimit(rawValue: stored) ?? .fiveMinutes
        }
        set { set(newValue.rawValue, forKey: RecordingKey.maxToggleDuration) }
    }

    /// То же в секундах — в таком виде это нужно шлюзу.
    var maxToggleDuration: TimeInterval { autoStopLimit.rawValue }
}
