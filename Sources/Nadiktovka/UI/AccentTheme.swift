import SwiftUI

/// Акцент приложения: цвет, которым подсвечены включённые переключатели,
/// активная вкладка, свечение фона и индикатор записи.
///
/// Иконку приложения этим не поменять — она лежит в подписанном бандле,
/// и запись туда сломала бы подпись, к которой привязаны разрешения.
/// Зато акцент видно каждый раз при открытии окна, а иконку — раз в неделю.
enum AccentTheme: String, CaseIterable, Identifiable {
    case violet
    case ocean
    case mint
    case sunset
    case rose
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .violet: return "Фиолетовый"
        case .ocean: return "Океан"
        case .mint: return "Мята"
        case .sunset: return "Закат"
        case .rose: return "Роза"
        case .graphite: return "Графит"
        }
    }

    /// Основной цвет: переключатели, активные элементы.
    var accent: Color {
        switch self {
        case .violet: return Color(red: 0.42, green: 0.34, blue: 0.96)
        case .ocean: return Color(red: 0.13, green: 0.55, blue: 0.96)
        case .mint: return Color(red: 0.22, green: 0.80, blue: 0.60)
        case .sunset: return Color(red: 1.00, green: 0.55, blue: 0.29)
        case .rose: return Color(red: 0.95, green: 0.35, blue: 0.60)
        case .graphite: return Color(red: 0.55, green: 0.58, blue: 0.64)
        }
    }

    /// Пара для свечения фона: тёплое пятно сверху и холодное снизу.
    /// Второй цвет соседний, а не контрастный: три и больше оттенка
    /// в одном фоне мешаются в грязь.
    var glowTop: Color {
        switch self {
        case .violet: return Color(red: 0.42, green: 0.34, blue: 0.86)
        case .ocean: return Color(red: 0.20, green: 0.45, blue: 0.90)
        case .mint: return Color(red: 0.16, green: 0.65, blue: 0.55)
        case .sunset: return Color(red: 0.90, green: 0.45, blue: 0.28)
        case .rose: return Color(red: 0.80, green: 0.30, blue: 0.55)
        case .graphite: return Color(red: 0.32, green: 0.35, blue: 0.42)
        }
    }

    var glowBottom: Color {
        switch self {
        case .violet: return Color(red: 0.30, green: 0.38, blue: 0.88)
        case .ocean: return Color(red: 0.12, green: 0.60, blue: 0.85)
        case .mint: return Color(red: 0.20, green: 0.50, blue: 0.62)
        case .sunset: return Color(red: 0.86, green: 0.28, blue: 0.42)
        case .rose: return Color(red: 0.58, green: 0.28, blue: 0.72)
        case .graphite: return Color(red: 0.26, green: 0.30, blue: 0.38)
        }
    }

    /// Ядро орба в окне настроек.
    var orbCore: (r: Double, g: Double, b: Double) {
        switch self {
        case .violet: return (0.30, 0.22, 0.62)
        case .ocean: return (0.14, 0.32, 0.66)
        case .mint: return (0.12, 0.46, 0.44)
        case .sunset: return (0.62, 0.30, 0.22)
        case .rose: return (0.56, 0.20, 0.44)
        case .graphite: return (0.24, 0.26, 0.32)
        }
    }

    /// Внешний ореол орба — светлее ядра.
    var orbHalo: (r: Double, g: Double, b: Double) {
        switch self {
        case .violet: return (0.76, 0.70, 0.98)
        case .ocean: return (0.62, 0.80, 1.00)
        case .mint: return (0.62, 0.95, 0.85)
        case .sunset: return (1.00, 0.78, 0.62)
        case .rose: return (0.98, 0.70, 0.86)
        case .graphite: return (0.78, 0.82, 0.88)
        }
    }
}

extension Settings {
    /// Выбранный акцент: ключ `ui.accent`.
    var accentTheme: AccentTheme {
        get { AccentTheme(rawValue: text("ui.accent", default: "violet")) ?? .violet }
        set { set(newValue.rawValue, forKey: "ui.accent") }
    }
}

extension Palette {
    /// Акцент читается из настроек: один источник правды на всё приложение.
    static var accent: Color { Settings.shared.accentTheme.accent }
}
