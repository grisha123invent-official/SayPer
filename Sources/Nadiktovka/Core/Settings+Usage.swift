import Foundation

/// Период, за который смотрят расходы. Живёт рядом с настройкой, потому что
/// выбор запоминается: человек открывает раздел, чтобы свериться с той же
/// цифрой, что и в прошлый раз, а не чтобы каждый раз переключать сегменты.
enum UsagePeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "7 дней"
        case .month: return "30 дней"
        case .allTime: return "Всё время"
        }
    }

    /// Сколько суток показывает график.
    ///
    /// У «всего времени» тоже 30: столбец на каждый день за год превращается
    /// в волосок, а вопрос «сколько я трачу» решается по последнему месяцу.
    /// Плитки при этом считают весь период — они и отвечают за итог.
    var chartDays: Int {
        switch self {
        case .week: return 7
        case .month, .allTime: return 30
        }
    }

    /// Начало периода или `nil`, если ограничения нет.
    func start(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .week:
            return calendar.startOfDay(for: now).addingTimeInterval(-6 * 24 * 3600)
        case .month:
            return calendar.startOfDay(for: now).addingTimeInterval(-29 * 24 * 3600)
        case .allTime:
            return nil
        }
    }
}

/// Настройки раздела «Расходы»: префикс ключей `usage.*`.
///
/// Здесь только состояние экрана. Сами агрегаты в `UserDefaults` не лежат —
/// они живут в `usage.json` (`UsageArchive`), потому что это данные, а не настройка.
extension Settings {
    private enum UsageKey {
        /// Выбранный период в шапке карточки «Расходы».
        static let period = "usage.period"
        /// Раскрыт ли список «цифрами» под графиком.
        static let showsNumbers = "usage.showsNumbers"
    }

    /// Период, на котором закрыли раздел в прошлый раз.
    var usagePeriod: UsagePeriod {
        get { UsagePeriod(rawValue: text(UsageKey.period)) ?? .month }
        set { set(newValue.rawValue, forKey: UsageKey.period) }
    }

    /// Список значений графика цифрами: график читается не всеми и не всегда,
    /// поэтому те же данные должны быть доступны текстом. Состояние запоминается.
    var usageShowsNumbers: Bool {
        get { flag(UsageKey.showsNumbers, default: false) }
        set { set(newValue, forKey: UsageKey.showsNumbers) }
    }
}
