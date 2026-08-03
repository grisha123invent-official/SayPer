import Foundation

/// Сочетание клавиш, привязанное к конкретному микрофону.
///
/// Второй способ выбирать устройство: не заранее в панели, а прямо в момент
/// диктовки — какую клавишу зажал, с того микрофона и пишется.
struct HotkeyRoute: Equatable, Codable, Identifiable {
    var id = UUID()
    var mask: UInt
    var keyCode: UInt16?
    /// Устройство в виде тега `MicrophoneChoice`: пусто — авто,
    /// `builtin` — встроенный, иначе UID.
    var deviceTag: String

    var binding: HotkeyBinding {
        get { HotkeyBinding(mask: mask, keyCode: keyCode) }
        set {
            mask = newValue.mask
            keyCode = newValue.keyCode
        }
    }

    var device: MicrophoneChoice { MicrophoneChoice(tag: deviceTag) }

    init(binding: HotkeyBinding, deviceTag: String) {
        self.mask = binding.mask
        self.keyCode = binding.keyCode
        self.deviceTag = deviceTag
    }
}

/// Как приложение решает, с какого микрофона писать.
enum MicRouting: String, CaseIterable, Identifiable {
    /// Устройство выбирается заранее в панели строки меню.
    case panel
    /// У каждого устройства своё сочетание клавиш.
    case perHotkey

    var id: String { rawValue }

    var title: String {
        switch self {
        // Коротко: в сегменты шириной 240 длинные подписи не влезали
        // и обрезались многоточием. Смысл раскрывает строка под ними.
        case .panel: return "В панели"
        case .perHotkey: return "На клавише"
        }
    }

    var summary: String {
        switch self {
        case .panel:
            return "Одно сочетание, устройство выбирается заранее в панели строки меню"
        case .perHotkey:
            return "У каждого микрофона своё сочетание — какое зажал, с того и пишется"
        }
    }
}

extension Settings {
    /// Ключ `audio.micRouting`.
    var micRouting: MicRouting {
        get { MicRouting(rawValue: text("audio.micRouting", default: "panel")) ?? .panel }
        set { set(newValue.rawValue, forKey: "audio.micRouting") }
    }

    /// Ключ `audio.hotkeyRoutes`. В режиме «клавиша на устройство» первая
    /// строка играет роль основного сочетания.
    var hotkeyRoutes: [HotkeyRoute] {
        get {
            let stored = decoded([HotkeyRoute].self, forKey: "audio.hotkeyRoutes") ?? []
            guard stored.isEmpty else { return stored }
            // Пустой список бесполезен: без строк не запишешь ничего.
            // Заводим одну из уже настроенного основного сочетания.
            return [HotkeyRoute(binding: hotkey, deviceTag: "")]
        }
        set { encode(newValue, forKey: "audio.hotkeyRoutes") }
    }
}
