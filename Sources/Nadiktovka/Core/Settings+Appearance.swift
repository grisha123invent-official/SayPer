import Foundation

/// Настройки оформления окна: префикс ключей `ui.*`.
///
/// Здесь живёт только то, что относится к внешнему виду и состоянию окна,
/// а не к работе диктовки. Значения по умолчанию задаются прямо в месте чтения —
/// общий `register(defaults:)` в `Settings` намеренно не расширяется.
extension Settings {
    private enum AppearanceKey {
        /// Последний открытый раздел окна настроек.
        static let lastSection = "ui.lastSection"
    }

    /// Раздел, на котором окно настроек закрыли в прошлый раз.
    ///
    /// Окно утилитарное: человек возвращается в него, чтобы дожать то, что
    /// начал, поэтому открывать всегда «Запись» — значит каждый раз заставлять
    /// его кликать заново. Неизвестное или устаревшее значение считается
    /// отсутствующим и откатывается к первому разделу.
    var lastSettingsSection: SettingsSection {
        get { SettingsSection(rawValue: text(AppearanceKey.lastSection)) ?? .general }
        set { set(newValue.rawValue, forKey: AppearanceKey.lastSection) }
    }
}
