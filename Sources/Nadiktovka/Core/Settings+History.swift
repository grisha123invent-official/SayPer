import Foundation

/// Настройки истории расшифровок: префикс ключей `history.*`.
///
/// Значения по умолчанию задаются прямо здесь, в месте чтения — общий
/// `register(defaults:)` в `Settings` намеренно не расширяется, иначе слайсы
/// начали бы спорить за один словарь.
extension Settings {
    private enum HistoryKey {
        /// Писать ли расшифровки на диск.
        static let enabled = "history.enabled"
        /// Сколько последних записей держать.
        static let limit = "history.limit"
    }

    /// Умолчания вынесены в тип, а не спрятаны в геттерах: на них смотрит
    /// и `HistoryStore`, и раздел настроек, и расходиться им нельзя.
    enum HistoryDefaults {
        static let enabled = true
        /// Двадцать записей — столько же, сколько показывает список и подменю
        /// в строке статуса. Больше никто не перечитывает.
        static let limit = 20
        /// Разумные границы: ноль превратил бы историю в выключенную втихую,
        /// а несколько тысяч — в файл, который читается заметно дольше запуска.
        static let limitRange = 1...200
    }

    /// «Хранить историю». Выключенная настройка означает не только «не писать»,
    /// но и «удалить то, что уже записано» — этим занимается `HistoryStore`.
    var historyEnabled: Bool {
        get { flag(HistoryKey.enabled, default: HistoryDefaults.enabled) }
        set { set(newValue, forKey: HistoryKey.enabled) }
    }

    /// Сколько последних расшифровок держать в списке и в архиве.
    ///
    /// Значение зажимается на чтении тоже: в файле настроек могло остаться
    /// что угодно от прошлых версий или от ручной правки `defaults write`.
    var historyLimit: Int {
        get { Self.clampedHistoryLimit(number(HistoryKey.limit, default: HistoryDefaults.limit)) }
        set { set(Self.clampedHistoryLimit(newValue), forKey: HistoryKey.limit) }
    }

    private static func clampedHistoryLimit(_ value: Int) -> Int {
        min(max(value, HistoryDefaults.limitRange.lowerBound),
            HistoryDefaults.limitRange.upperBound)
    }
}
