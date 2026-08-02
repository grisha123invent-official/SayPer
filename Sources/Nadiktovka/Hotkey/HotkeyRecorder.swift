import AppKit
import SwiftUI

extension Notification.Name {
    /// Пока идёт запись сочетания, глобальный перехват надо приостановить,
    /// иначе нажатие текущего хоткея запустит диктовку прямо в настройках.
    static let hotkeyRecordingBegan = Notification.Name("hotkeyRecordingBegan")
    static let hotkeyRecordingEnded = Notification.Name("hotkeyRecordingEnded")
}

/// Поле «нажми сочетание»: кликаешь, зажимаешь клавиши — они записываются.
///
/// Оформление — `components.md` §2: 190 × 28, `radiusField` 6 с непрерывной
/// кривизной, значение 13pt medium, обводка `fieldBorder`, пять состояний плюс
/// запись и ошибка. Фон и обводка живут на `CALayer`, а не в `NSBezierPath`:
/// `NSBezierPath(roundedRect:xRadius:)` умеет только circular-скругление,
/// которое `tokens.md` §3 запрещает, а `layer.cornerCurve = .continuous` даёт
/// тот самый squircle. В `draw(_:)` остаётся только текст — у слоя фон рисуется
/// под содержимым, обводка поверх, так что порядок сохраняется.
final class HotkeyRecorderView: NSView {
    var binding: HotkeyBinding = .rightOptionOnly {
        didSet { refreshStyle() }
    }
    var onChange: ((HotkeyBinding) -> Void)?
    /// Клик по иконке сброса внутри поля.
    var onReset: (() -> Void)?

    /// Поле выключено: `components.md` §2 требует, чтобы оно гасло, а не исчезало.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled {
                if isRecording { stopRecording() }
                isHovered = false
            }
            refreshStyle()
        }
    }

    /// Иконка сброса живёт внутри поля отдельной кнопкой (`components.md` §2):
    /// прижата к правому краю с отступом 6, видна при наведении **и** при фокусе.
    /// Настоящий `NSButton`, а не рисунок, — у него есть тултип, роль для
    /// VoiceOver и своё место в обходе по Tab. Поле от её появления и исчезновения
    /// не меняет ширину: раньше сброс стоял снаружи и сдвигал поле на 28pt
    /// ровно в тот момент, когда человек целится в клавиши.
    private lazy var resetButton: NSButton = makeResetButton()

    private var isRecording = false {
        didSet {
            refreshStyle()
            NotificationCenter.default.post(
                name: isRecording ? .hotkeyRecordingBegan : .hotkeyRecordingEnded,
                object: nil
            )
        }
    }

    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            refreshStyle()
        }
    }

    private var isFocused = false {
        didSet {
            guard isFocused != oldValue else { return }
            refreshStyle()
        }
    }

    /// Максимальный набор модификаторов за текущее нажатие: если зажать ⌃⌥
    /// и отпускать по одной, запомнить надо обе.
    private var maxMask: UInt = 0
    private var hint: String?

    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Своё кольцо фокуса не рисуем: окно делает поле первым откликающимся
        // сразу при открытии, и синяя рамка висела постоянно, будто идёт
        // запись сочетания. Режим записи и так виден по подсветке поля.
        focusRingType = .none
        addSubview(resetButton)
        refreshStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    override var acceptsFirstResponder: Bool { isEnabled }
    override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 28) }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        guard !isRecording else {
            stopRecording()
            return
        }
        window?.makeFirstResponder(self)
        maxMask = 0
        hint = nil
        isRecording = true
    }

    override func becomeFirstResponder() -> Bool {
        isFocused = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { stopRecording() }
        isFocused = false
        return true
    }

    // MARK: - Наведение и фокус

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = isEnabled
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    // MARK: - Сброс

    private func makeResetButton() -> NSButton {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "arrow.uturn.backward",
            accessibilityDescription: "Вернуть правый ⌥"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Вернуть правый ⌥"
        button.setAccessibilityLabel("Вернуть правый ⌥")
        button.target = self
        button.action = #selector(resetTapped)
        button.isHidden = true
        return button
    }

    @objc private func resetTapped() {
        onReset?()
    }

    /// Сбрасывать нечего, если значение уже по умолчанию (`components.md` §2).
    private var showsReset: Bool {
        isEnabled && !isRecording && binding != .rightOptionOnly && (isHovered || isFocused)
    }

    override func layout() {
        super.layout()
        let side: CGFloat = 16
        resetButton.frame = NSRect(
            x: bounds.maxX - 6 - side,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
    }

    /// Фокусное кольцо у обычного `NSView` не появляется само: маску надо задать
    /// руками, иначе поле — единственный контрол раздела без состояния «фокус»
    /// (`tokens.md` §11).
    override func drawFocusRingMask() {
        NSBezierPath(
            roundedRect: bounds,
            xRadius: Palette.radiusField,
            yRadius: Palette.radiusField
        ).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        noteFocusRingMaskChanged()
        needsLayout = true
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
            refreshStyle()
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
            refreshStyle()
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

    /// Порядок важен: `isRecording` перерисовывает поле в своём `didSet`,
    /// и к этому моменту подсказка об ошибке уже должна быть снята.
    private func stopRecording() {
        maxMask = 0
        hint = nil
        isRecording = false
    }

    // MARK: - Отрисовка

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshStyle()
    }

    /// Заливка и обводка — на слое, текст — в `draw(_:)`.
    private func refreshStyle() {
        guard let layer else { return }
        layer.cornerRadius = Palette.radiusField
        layer.cornerCurve = .continuous
        layer.borderWidth = borderWidth
        // Динамические цвета отдают `cgColor` для той темы, что сейчас текущая,
        // поэтому их надо разрешать в контексте своей внешности.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = fillColor.cgColor
            layer.borderColor = strokeColor.cgColor
        }
        resetButton.isHidden = !showsReset
        needsDisplay = true
    }

    private var borderWidth: CGFloat {
        (isRecording || hint != nil) ? 2 : 1
    }

    private var fillColor: NSColor {
        if !isEnabled { return dimmed(.controlBackgroundColor, 0.5) }
        if hint != nil { return NSColor.systemOrange.withAlphaComponent(0.10) }
        if isRecording { return NSColor.controlAccentColor.withAlphaComponent(0.12) }
        return isHovered ? hoveredFill : .controlBackgroundColor
    }

    private var strokeColor: NSColor {
        if !isEnabled { return dimmed(Palette.fieldBorderNS, 0.5) }
        if hint != nil { return .systemOrange }
        if isRecording { return .controlAccentColor }
        return Palette.fieldBorderNS
    }

    /// Наведение — `surfaceRowHover` поверх заливки поля. На слое лежит ровно
    /// один цвет, поэтому полупрозрачный уровень подмешивается заранее.
    private var hoveredFill: NSColor {
        let base = NSColor.controlBackgroundColor
        guard let tint = Palette.surfaceRowHoverNS.usingColorSpace(.sRGB) else { return base }
        return base.blended(withFraction: tint.alphaComponent, of: tint.withAlphaComponent(1))
            ?? base
    }

    /// Динамический `NSColor` не отдаёт компоненты, пока его не привели
    /// к конкретному пространству, — отсюда явное преобразование.
    private func dimmed(_ color: NSColor, _ factor: CGFloat) -> NSColor {
        guard let solid = color.usingColorSpace(.sRGB) else { return color }
        return solid.withAlphaComponent(solid.alphaComponent * factor)
    }

    override func draw(_ dirtyRect: NSRect) {
        let text: String
        let color: NSColor
        let font: NSFont

        if let hint {
            text = hint
            color = .systemOrange
            // Ошибка длиннее значения и в 13pt не помещается в 190pt поля.
            font = .systemFont(ofSize: 11, weight: .regular)
        } else if isRecording {
            text = maxMask == 0
                ? "Зажми сочетание…"
                : HotkeyBinding(mask: maxMask, keyCode: nil).displayString
            color = .controlAccentColor
            font = .systemFont(ofSize: 13, weight: .semibold)
        } else {
            text = binding.displayString
            color = isEnabled ? .labelColor : .tertiaryLabelColor
            // `tokens.md` §6: значение хоткея — 13/medium, а не regular.
            font = .systemFont(ofSize: 13, weight: .medium)
        }

        let string = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color]
        )
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
        apply(context: context, to: view)
        return view
    }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        if view.binding != hotkey {
            view.binding = hotkey
        }
        apply(context: context, to: view)
    }

    private func apply(context: Context, to view: HotkeyRecorderView) {
        view.onChange = { hotkey = $0 }
        view.onReset = { hotkey = .rightOptionOnly }
        view.isEnabled = context.environment.isEnabled
    }
}
