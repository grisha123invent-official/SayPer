import Foundation

/// Что делать со звуком компьютера, пока идёт диктовка: префикс ключей `audio.*`.
extension Settings {
    private enum AudioKey {
        static let duckMode = "audio.duckMode"
        static let duckLevel = "audio.duckLevel"
    }

    /// По умолчанию звук убавляется, а не выключается: полная тишина сбивает,
    /// когда диктуешь под музыку, — непонятно, играет ли ещё трек.
    var duckMode: OutputDucker.Mode {
        get { OutputDucker.Mode(rawValue: text(AudioKey.duckMode, default: "dim")) ?? .dim }
        set { set(newValue.rawValue, forKey: AudioKey.duckMode) }
    }

    /// Доля прежней громкости в режиме «Убавить»: 0.2 — это пятая часть.
    /// Хранится долей, а не процентом, чтобы не пересчитывать при каждом чтении.
    var duckLevel: Double {
        get {
            let stored = decimal(AudioKey.duckLevel, default: 0.2)
            return min(max(stored, 0.05), 0.9)
        }
        set { set(min(max(newValue, 0.05), 0.9), forKey: AudioKey.duckLevel) }
    }
}
