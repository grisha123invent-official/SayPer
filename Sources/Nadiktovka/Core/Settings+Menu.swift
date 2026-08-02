import Foundation

/// Настройки меню в строке статуса: префикс ключей `menu.*`.
///
/// В окне настроек этих переключателей нет и не будет: меню — не раздел
/// приложения, а его витрина, и настраивать витрину человеку незачем.
/// Ключи существуют по двум причинам: числа, от которых зависит вёрстка меню,
/// должны лежать в одном месте с объяснением, а нестандартный случай
/// («покажи десять последних») чинится через `defaults write` без пересборки.
extension Settings {
    private enum MenuKey {
        /// Сколько последних расшифровок показывает подменю «История».
        static let historyCount = "menu.historyCount"
        /// Сколько символов текста влезает в пункт меню.
        static let previewLength = "menu.previewLength"
    }

    /// Умолчания вынесены в тип: на них смотрит и подменю «История»,
    /// и строка «Скопировать…», расходиться им нельзя.
    enum MenuDefaults {
        /// Пять записей — ровно столько, сколько человек помнит из последнего
        /// часа работы. Дальше подменю превращается в список, а для списка
        /// есть раздел «История» в окне.
        static let historyCount = 5
        /// Больше десяти — уже окно, меньше одной — выключенное подменю,
        /// про которое никто не догадается.
        static let historyCountRange = 1...10

        /// Превью текста, символов. Двадцать восемь — верх коридора 24–28:
        /// на сорока меню разъезжается до ~400pt и перестаёт помещаться
        /// под иконкой, на двадцати из фразы не узнать, какая она была.
        static let previewLength = 28
        static let previewLengthRange = 16...40
    }

    /// Сколько последних расшифровок показывает подменю «История».
    ///
    /// Значение зажимается и на чтении: в файле настроек могло остаться
    /// что угодно от ручной правки `defaults write`.
    var menuHistoryCount: Int {
        get { Self.clamped(number(MenuKey.historyCount, default: MenuDefaults.historyCount),
                           to: MenuDefaults.historyCountRange) }
        set { set(Self.clamped(newValue, to: MenuDefaults.historyCountRange),
                  forKey: MenuKey.historyCount) }
    }

    /// Длина превью текста в пунктах меню, символы.
    var menuPreviewLength: Int {
        get { Self.clamped(number(MenuKey.previewLength, default: MenuDefaults.previewLength),
                           to: MenuDefaults.previewLengthRange) }
        set { set(Self.clamped(newValue, to: MenuDefaults.previewLengthRange),
                  forKey: MenuKey.previewLength) }
    }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
