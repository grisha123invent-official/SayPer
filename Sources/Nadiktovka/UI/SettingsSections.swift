import Foundation

/// Разделы окна настроек. Порядок — по убыванию частоты обращения
/// (`design/ia.md`): то, что настраивают в первую неделю, идёт первым,
/// «поставил и забыл» — в конец. Состав заморожен: новые разделы не заводятся.
enum SettingsSection: String, CaseIterable, Identifiable {
    /// Диктовка: сочетание, режим, индикатор, звуки, модель, язык,
    /// словарь, чистка, способ вставки — весь путь от клавиши до текста.
    case general
    /// История последних расшифровок.
    case history
    /// Кастомизация: акцент и тема оформления.
    case customization
    /// Ключ и расходы: статистика, API-ключ, доступ к клавиатуре, автозапуск.
    case system
    /// О программе: версия, связь с разработчиком, диагностика, помощник.
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Диктовка"
        case .history: return "История"
        case .customization: return "Кастомизация"
        case .system: return "Ключ и расходы"
        case .about: return "О программе"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "mic"
        case .history: return "clock.arrow.circlepath"
        case .customization: return "paintpalette"
        case .system: return "key"
        case .about: return "info.circle"
        }
    }

    /// Клавиша для ⌘1…⌘5.
    var shortcut: Character {
        switch self {
        case .general: return "1"
        case .history: return "2"
        case .customization: return "3"
        case .system: return "4"
        case .about: return "5"
        }
    }
}

extension Notification.Name {
    /// Просьба показать отчёт диагностики. Публикует раздел «Ключ и доступ»,
    /// слушает `AppDelegate` — он единственный знает состояние перехвата.
    static let showDiagnostics = Notification.Name("showDiagnostics")
}
