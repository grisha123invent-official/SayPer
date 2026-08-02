import AppKit

/// Биты модификаторов, различающие левую и правую клавишу.
/// Они лежат в младших разрядах `NSEvent.modifierFlags.rawValue` —
/// обычные `.option`/`.command` сторону не различают.
enum ModifierBit {
    static let leftControl: UInt  = 0x00001
    static let leftShift: UInt    = 0x00002
    static let rightShift: UInt   = 0x00004
    static let leftCommand: UInt  = 0x00008
    static let rightCommand: UInt = 0x00010
    static let leftOption: UInt   = 0x00020
    static let rightOption: UInt  = 0x00040
    static let rightControl: UInt = 0x02000
    /// У Fn стороны нет, берём обычный флаг.
    static let function: UInt     = UInt(NSEvent.ModifierFlags.function.rawValue)

    /// Только эти биты нас интересуют; Caps Lock и прочее игнорируем.
    static let all: UInt = leftControl | leftShift | rightShift | leftCommand
        | rightCommand | leftOption | rightOption | rightControl | function

    /// Клавиши, которые сами по себе поднимают флаг Fn на ноутбуках —
    /// при записи хоткея этот флаг с них надо снимать.
    static let impliesFunction: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,   // F1…F12
        123, 124, 125, 126,                                        // стрелки
        115, 119, 116, 121, 117                                    // Home, End, PgUp, PgDn, Fwd Delete
    ]
}

/// Сочетание клавиш: набор физических модификаторов и, опционально, обычная клавиша.
struct HotkeyBinding: Equatable {
    /// Требуемые биты модификаторов (со сторонами).
    var mask: UInt
    /// Обычная клавиша; nil — хоткей только из модификаторов.
    var keyCode: UInt16?

    static let rightOptionOnly = HotkeyBinding(mask: ModifierBit.rightOption, keyCode: nil)

    var isEmpty: Bool { mask == 0 && keyCode == nil }

    /// Есть ли смысл в таком хоткее: голая обычная клавиша без модификаторов
    /// заблокировала бы обычный ввод.
    var isValid: Bool {
        if keyCode == nil { return mask != 0 }
        return mask != 0
    }

    /// Зажат ли хоткей прямо сейчас, судя по маске модификаторов и состоянию клавиши.
    func isHeld(currentMask: UInt, pressedKey: UInt16?) -> Bool {
        guard mask != 0, (currentMask & mask) == mask else { return false }
        guard let keyCode else { return true }
        return pressedKey == keyCode
    }

    // MARK: - Человекочитаемое описание

    var displayString: String {
        guard !isEmpty else { return "не задано" }

        // Одиночный модификатор без клавиши — самый частый случай,
        // для него сторону пишем словом: «Правый ⌥».
        if keyCode == nil, let single = Self.singleModifierName(mask) {
            return single
        }

        var result = Self.symbols(for: mask)
        if let keyCode {
            result += Self.keyName(keyCode)
        }
        return result
    }

    private static func singleModifierName(_ mask: UInt) -> String? {
        switch mask {
        case ModifierBit.leftOption: return "Левый ⌥"
        case ModifierBit.rightOption: return "Правый ⌥"
        case ModifierBit.leftCommand: return "Левый ⌘"
        case ModifierBit.rightCommand: return "Правый ⌘"
        case ModifierBit.leftControl: return "Левый ⌃"
        case ModifierBit.rightControl: return "Правый ⌃"
        case ModifierBit.leftShift: return "Левый ⇧"
        case ModifierBit.rightShift: return "Правый ⇧"
        case ModifierBit.function: return "Fn"
        default: return nil
        }
    }

    /// Символы в привычном для macOS порядке: ⌃⌥⇧⌘.
    private static func symbols(for mask: UInt) -> String {
        var result = ""
        if mask & ModifierBit.function != 0 { result += "fn" }
        if mask & (ModifierBit.leftControl | ModifierBit.rightControl) != 0 { result += "⌃" }
        if mask & (ModifierBit.leftOption | ModifierBit.rightOption) != 0 { result += "⌥" }
        if mask & (ModifierBit.leftShift | ModifierBit.rightShift) != 0 { result += "⇧" }
        if mask & (ModifierBit.leftCommand | ModifierBit.rightCommand) != 0 { result += "⌘" }
        return result
    }

    /// Названия по физическому положению клавиши (раскладка ANSI),
    /// чтобы подпись не менялась при переключении на кириллицу.
    static func keyName(_ keyCode: UInt16) -> String {
        if let name = names[keyCode] { return name }
        return "Клавиша \(keyCode)"
    }

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".",
        50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
}
