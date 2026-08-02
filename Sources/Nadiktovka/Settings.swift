import AppKit

/// Как доставлять расшифрованный текст в активное поле.
enum InsertMode: String, CaseIterable, Identifiable {
    case paste
    case type
    case clipboardOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste: return "Вставить (⌘V, буфер восстанавливается)"
        case .type: return "Напечатать посимвольно"
        case .clipboardOnly: return "Только скопировать в буфер"
        }
    }
}

enum TranscriptionModel: String, CaseIterable, Identifiable {
    case whisper1 = "whisper-1"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whisper1: return "whisper-1 (классический Whisper)"
        case .gpt4oTranscribe: return "gpt-4o-transcribe (точнее)"
        case .gpt4oMiniTranscribe: return "gpt-4o-mini-transcribe (дешевле)"
        }
    }
}

/// Настройки приложения. Всё, кроме API-ключа, лежит в UserDefaults.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let hotkeyMask = "hotkeyMask"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        /// Значение прежних версий: строка вида "rightOption".
        static let legacyHotkey = "hotkey"
        static let model = "model"
        static let language = "language"
        static let insertMode = "insertMode"
        static let playSounds = "playSounds"
        static let showIndicator = "showIndicator"
        static let vocabulary = "vocabulary"
        static let cleanup = "cleanup"
    }

    private init() {
        defaults.register(defaults: [
            Key.model: TranscriptionModel.whisper1.rawValue,
            Key.language: "ru",
            Key.insertMode: InsertMode.paste.rawValue,
            Key.playSounds: true,
            Key.showIndicator: true,
            Key.vocabulary: "",
            Key.cleanup: false
        ])
    }

    var hotkey: HotkeyBinding {
        get {
            guard defaults.object(forKey: Key.hotkeyMask) != nil else {
                return migratedHotkey()
            }
            let mask = UInt(defaults.integer(forKey: Key.hotkeyMask))
            let stored = defaults.integer(forKey: Key.hotkeyKeyCode)
            let binding = HotkeyBinding(
                mask: mask,
                keyCode: stored >= 0 ? UInt16(stored) : nil
            )
            return binding.isValid ? binding : .rightOptionOnly
        }
        set {
            defaults.set(Int(newValue.mask), forKey: Key.hotkeyMask)
            defaults.set(newValue.keyCode.map(Int.init) ?? -1, forKey: Key.hotkeyKeyCode)
        }
    }

    /// Перенос настройки из версий, где хоткей выбирался из списка.
    private func migratedHotkey() -> HotkeyBinding {
        switch defaults.string(forKey: Key.legacyHotkey) {
        case "leftOption": return HotkeyBinding(mask: ModifierBit.leftOption, keyCode: nil)
        case "rightCommand": return HotkeyBinding(mask: ModifierBit.rightCommand, keyCode: nil)
        case "rightControl": return HotkeyBinding(mask: ModifierBit.rightControl, keyCode: nil)
        case "fn": return HotkeyBinding(mask: ModifierBit.function, keyCode: nil)
        default: return .rightOptionOnly
        }
    }

    var model: TranscriptionModel {
        get { TranscriptionModel(rawValue: defaults.string(forKey: Key.model) ?? "") ?? .whisper1 }
        set { defaults.set(newValue.rawValue, forKey: Key.model) }
    }

    /// Код языка ISO-639-1 или "" для автоопределения.
    var language: String {
        get { defaults.string(forKey: Key.language) ?? "ru" }
        set { defaults.set(newValue, forKey: Key.language) }
    }

    var insertMode: InsertMode {
        get { InsertMode(rawValue: defaults.string(forKey: Key.insertMode) ?? "") ?? .paste }
        set { defaults.set(newValue.rawValue, forKey: Key.insertMode) }
    }

    var playSounds: Bool {
        get { defaults.bool(forKey: Key.playSounds) }
        set { defaults.set(newValue, forKey: Key.playSounds) }
    }

    var showIndicator: Bool {
        get { defaults.bool(forKey: Key.showIndicator) }
        set { defaults.set(newValue, forKey: Key.showIndicator) }
    }

    /// Подсказка для Whisper: имена, термины, названия — их модель начинает узнавать.
    var vocabulary: String {
        get { defaults.string(forKey: Key.vocabulary) ?? "" }
        set { defaults.set(newValue, forKey: Key.vocabulary) }
    }

    /// Прогонять ли расшифровку через gpt-4o-mini для чистки пунктуации и слов-паразитов.
    var cleanup: Bool {
        get { defaults.bool(forKey: Key.cleanup) }
        set { defaults.set(newValue, forKey: Key.cleanup) }
    }

    var apiKey: String? { Keychain.readAPIKey() }
}
