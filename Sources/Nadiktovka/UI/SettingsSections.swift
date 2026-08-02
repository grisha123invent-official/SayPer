import Foundation

/// Разделы окна настроек. Порядок — по убыванию частоты обращения
/// (`design/ia.md`): то, что настраивают в первую неделю, идёт первым,
/// «поставил и забыл» — в конец. Состав заморожен: новые разделы не заводятся.
enum SettingsSection: String, CaseIterable, Identifiable {
    /// Запись: горячая клавиша, режим, индикатор, звуки.
    case general
    /// Текст: модель, язык, чистка, словарь, способ вставки.
    case dictation
    /// История последних расшифровок.
    case history
    /// Расходы: минуты, слова, оценка стоимости.
    case usage
    /// Ключ и доступ: API-ключ, доступ к клавиатуре, автозапуск.
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Запись"
        case .dictation: return "Текст"
        case .history: return "История"
        case .usage: return "Расходы"
        case .system: return "Ключ и доступ"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "mic"
        case .dictation: return "text.alignleft"
        case .history: return "clock.arrow.circlepath"
        case .usage: return "chart.bar"
        case .system: return "key"
        }
    }

    /// Клавиша для ⌘1…⌘5.
    var shortcut: Character {
        switch self {
        case .general: return "1"
        case .dictation: return "2"
        case .history: return "3"
        case .usage: return "4"
        case .system: return "5"
        }
    }
}
