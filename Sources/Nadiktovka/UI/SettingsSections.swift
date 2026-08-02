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
    /// Расходы: минуты, слова, оценка стоимости.
    case usage
    /// Ключ и доступ: API-ключ, доступ к клавиатуре, автозапуск.
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Диктовка"
        case .history: return "История"
        case .usage: return "Расходы"
        case .system: return "Ключ и доступ"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "mic"
        case .history: return "clock.arrow.circlepath"
        case .usage: return "chart.bar"
        case .system: return "key"
        }
    }

    /// Клавиша для ⌘1…⌘4.
    var shortcut: Character {
        switch self {
        case .general: return "1"
        case .history: return "2"
        case .usage: return "3"
        case .system: return "4"
        }
    }
}

extension Notification.Name {
    /// Просьба показать отчёт диагностики. Публикует раздел «Ключ и доступ»,
    /// слушает `AppDelegate` — он единственный знает состояние перехвата.
    static let showDiagnostics = Notification.Name("showDiagnostics")
}
