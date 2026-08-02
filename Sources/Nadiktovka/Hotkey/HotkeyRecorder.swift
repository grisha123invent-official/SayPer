import AppKit
import SwiftUI

extension Notification.Name {
    /// Пока идёт запись сочетания, глобальный перехват надо приостановить,
    /// иначе нажатие текущего хоткея запустит диктовку прямо в настройках.
    static let hotkeyRecordingBegan = Notification.Name("hotkeyRecordingBegan")
    static let hotkeyRecordingEnded = Notification.Name("hotkeyRecordingEnded")
}

/// Поле «нажми сочетание»: кликаешь, зажимаешь клавиши — они записываются.
final class HotkeyRecorderView: NSView {
    var binding: HotkeyBinding = .rightOptionOnly {
        didSet { needsDisplay = true }
    }
    var onChange: ((HotkeyBinding) -> Void)?

    private var isRecording = false {
        didSet {
            needsDisplay = true
            NotificationCenter.default.post(
                name: isRecording ? .hotkeyRecordingBegan : .hotkeyRecordingEnded,
                object: nil
            )
        }
    }

    /// Максимальный набор модификаторов за текущее нажатие: если зажать ⌃⌥
    /// и отпускать по одной, запомнить надо обе.
    private var maxMask: UInt = 0
    private var hint: String?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 26) }

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else {
            stopRecording()
            return
        }
        window?.makeFirstResponder(self)
        maxMask = 0
        hint = nil
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { stopRecording() }
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        let mask = UInt(event.modifierFlags.rawValue) & ModifierBit.all

        if mask == 0 {
            // Все клавиши отпущены — сочетание из одних модификаторов готово.
            if maxMask != 0 {
                commit(HotkeyBinding(mask: maxMask, keyCode: nil))
            }
        } else if mask.nonzeroBitCount > maxMask.nonzeroBitCount {
            maxMask = mask
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        var mask = UInt(event.modifierFlags.rawValue) & ModifierBit.all
        let keyCode = event.keyCode

        // Esc без модификаторов — выход без изменений.
        if keyCode == 53, mask == 0 {
            stopRecording()
            return
        }

        guard mask != 0 else {
            hint = "Нужен хотя бы один модификатор"
            needsDisplay = true
            return
        }

        // Стрелки и F-клавиши сами поднимают флаг Fn — он тут лишний.
        if ModifierBit.impliesFunction.contains(keyCode) {
            mask &= ~ModifierBit.function
        }

        commit(HotkeyBinding(mask: mask, keyCode: keyCode))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Пока пишем сочетание, системные шорткаты вроде ⌘W не должны срабатывать.
        guard isRecording else { return false }
        keyDown(with: event)
        return true
    }

    private func commit(_ newBinding: HotkeyBinding) {
        guard newBinding.isValid else {
            stopRecording()
            return
        }
        binding = newBinding
        onChange?(newBinding)
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        maxMask = 0
        hint = nil
        needsDisplay = true
    }

    // MARK: - Отрисовка

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSColor.controlAccentColor.setStroke()
        } else {
            NSColor.controlBackgroundColor.setFill()
            NSColor.separatorColor.setStroke()
        }
        path.fill()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String
        let color: NSColor

        if let hint {
            text = hint
            color = .systemOrange
        } else if isRecording {
            text = maxMask == 0
                ? "Зажми сочетание…"
                : HotkeyBinding(mask: maxMask, keyCode: nil).displayString
            color = .controlAccentColor
        } else {
            text = binding.displayString
            color = .labelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isRecording ? .semibold : .regular),
            .foregroundColor: color
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        ))
    }
}

/// Обёртка рекордера для SwiftUI.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: HotkeyBinding

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.binding = hotkey
        view.onChange = { hotkey = $0 }
        return view
    }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        if view.binding != hotkey {
            view.binding = hotkey
        }
        view.onChange = { hotkey = $0 }
    }
}
