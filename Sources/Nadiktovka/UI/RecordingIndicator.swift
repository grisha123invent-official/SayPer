import AppKit
import QuartzCore

/// Плавающая стеклянная пилюля: показывает, что микрофон слушает,
/// и что происходит с записью дальше.
final class RecordingIndicator {
    enum State: Equatable {
        case recording
        case transcribing
        case error(String)
    }

    private var panel: NSPanel?
    private var glass: GlassIndicatorView?
    private var hideTimer: Timer?
    private var hint: String?

    func show(_ state: State) {
        hideTimer?.invalidate()
        hideTimer = nil

        guard Settings.shared.showIndicator else { return }

        let panel = self.panel ?? makePanel()
        glass?.hint = hint
        glass?.apply(state)
        resize(panel, animated: panel.isVisible)
        position(panel)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            glass?.playAppearance()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }

        if case .error = state {
            hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }

    func update(level: Float) {
        glass?.level = level
    }

    /// Подсказка режима записи рядом с подписью: `nil` — подсказки нет.
    /// В режиме удержания она не нужна, её задаёт «Нажал-нажал».
    func setHint(_ hint: String?) {
        guard hint != self.hint else { return }
        self.hint = hint
        glass?.hint = hint

        if let panel, panel.isVisible {
            resize(panel, animated: true)
        }
    }

    /// Секунды ожидания ответа — чтобы длинная расшифровка не выглядела зависшей.
    func update(elapsed: TimeInterval) {
        glass?.elapsed = elapsed
        // Подпись стала длиннее — пилюля должна за ней успеть.
        if let panel, panel.isVisible {
            resize(panel, animated: true)
        }
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil

        guard let panel, panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    private func makePanel() -> NSPanel {
        let frame = NSRect(x: 0, y: 0, width: 180, height: 38)
        let view = GlassIndicatorView(frame: frame)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        self.panel = panel
        self.glass = view
        return panel
    }

    private func resize(_ panel: NSPanel, animated: Bool) {
        guard let glass else { return }

        let width = max(120, min(glass.preferredWidth, 360))
        guard abs(width - panel.frame.width) > 1 else { return }

        var frame = panel.frame
        frame.origin.x -= (width - frame.width) / 2
        frame.size.width = width

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: false)
        }
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 96
        ))
    }
}

// MARK: - Стекло

/// Слоистое «жидкое стекло»: размытие подложки, блик по верхней кромке,
/// тонкая светлая обводка и мягкое внутреннее свечение.
private final class GlassIndicatorView: NSView {
    var level: Float = 0 {
        didSet {
            // Полоски тянутся к новому уровню, а не прыгают на него.
            smoothed = smoothed * 0.55 + level * 0.45
        }
    }

    var elapsed: TimeInterval = 0 {
        didSet { content.elapsed = elapsed }
    }

    var hint: String? {
        didSet { content.hint = hint }
    }

    /// Пилюля тянется под длину подписи, чтобы не оставалось пустого места.
    var preferredWidth: CGFloat {
        content.preferredWidth(height: bounds.height)
    }

    private var smoothed: Float = 0 {
        didSet { content.level = smoothed }
    }

    private let blur = NSVisualEffectView()
    private let content = IndicatorContentView()
    private let highlight = CAGradientLayer()
    private let rim = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        buildLayers()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func apply(_ state: RecordingIndicator.State) {
        content.state = state

        let tint: NSColor
        switch state {
        case .recording: tint = NSColor(calibratedRed: 0.35, green: 0.62, blue: 1.0, alpha: 1)
        case .transcribing: tint = NSColor(calibratedRed: 0.55, green: 0.45, blue: 1.0, alpha: 1)
        case .error: tint = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.35, alpha: 1)
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        rim.borderColor = tint.withAlphaComponent(0.28).cgColor
        CATransaction.commit()
    }

    /// Лёгкий «выезд» при появлении, как у системных панелей.
    func playAppearance() {
        guard let layer else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.0
        scale.duration = 0.28
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1.0)
        layer.add(scale, forKey: "appear")
    }

    private func buildLayers() {
        let radius = bounds.height / 2

        blur.frame = bounds
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = radius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        addSubview(blur)

        // Блик сверху: свет как будто падает на выпуклое стекло.
        highlight.frame = bounds
        highlight.cornerRadius = radius
        highlight.cornerCurve = .continuous
        highlight.colors = [
            NSColor.white.withAlphaComponent(0.20).cgColor,
            NSColor.white.withAlphaComponent(0.04).cgColor,
            NSColor.clear.cgColor
        ]
        highlight.locations = [0.0, 0.35, 1.0]
        highlight.startPoint = CGPoint(x: 0.5, y: 1.0)
        highlight.endPoint = CGPoint(x: 0.5, y: 0.0)
        blur.layer?.addSublayer(highlight)

        // Кромка стекла.
        rim.frame = bounds
        rim.cornerRadius = radius
        rim.cornerCurve = .continuous
        rim.borderWidth = 1
        rim.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.addSublayer(rim)

        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    override func layout() {
        super.layout()
        let radius = bounds.height / 2
        highlight.frame = bounds
        highlight.cornerRadius = radius
        rim.frame = bounds
        rim.cornerRadius = radius
        blur.layer?.cornerRadius = radius
    }
}

// MARK: - Содержимое

/// Иконка, эквалайзер и подпись поверх стекла.
private final class IndicatorContentView: NSView {
    var state: RecordingIndicator.State = .recording {
        didSet { needsDisplay = true }
    }

    var level: Float = 0 {
        didSet { needsDisplay = true }
    }

    var elapsed: TimeInterval = 0 {
        didSet { needsDisplay = true }
    }

    var hint: String? {
        didSet { needsDisplay = true }
    }

    private var phase: CGFloat = 0
    private var timer: Timer?

    private let barCount = 5
    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 3.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.phase += 0.13
            self?.needsDisplay = true
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    deinit { timer?.invalidate() }

    /// Отступ от края стекла до эквалайзера и после текста.
    private let padding: CGFloat = 13
    /// Просвет между полосками и подписью.
    private let gap: CGFloat = 9

    override func draw(_ dirtyRect: NSRect) {
        let tint = tintColor()
        let barsRight = drawBars(tint: tint)
        drawTitle(startingAt: barsRight)
    }

    private func tintColor() -> NSColor {
        switch state {
        case .recording: return NSColor(calibratedRed: 0.40, green: 0.68, blue: 1.0, alpha: 1)
        case .transcribing: return NSColor(calibratedRed: 0.62, green: 0.52, blue: 1.0, alpha: 1)
        case .error: return NSColor(calibratedRed: 1.0, green: 0.60, blue: 0.40, alpha: 1)
        }
    }

    /// Эквалайзер: во время записи пляшет по громкости, при расшифровке — своя волна.
    /// Возвращает правую границу, чтобы подпись встала вплотную.
    private func drawBars(tint: NSColor) -> CGFloat {
        let left = padding
        let maxHeight = bounds.height - 18

        let gradient = NSGradient(colors: [
            tint,
            tint.blended(withFraction: 0.35, of: .white) ?? tint
        ])

        for index in 0..<barCount {
            let wave: CGFloat
            switch state {
            case .recording:
                let amplitude = CGFloat(max(level, 0.06))
                wave = amplitude * (0.5 + 0.5 * abs(sin(phase * 1.6 + CGFloat(index) * 0.8)))
            case .transcribing:
                wave = 0.22 + 0.5 * abs(sin(phase * 1.9 + CGFloat(index) * 0.75))
            case .error:
                wave = 0.28
            }

            let height = max(5, maxHeight * min(wave, 1))
            let rect = NSRect(
                x: left + CGFloat(index) * (barWidth + barSpacing),
                y: (bounds.height - height) / 2,
                width: barWidth,
                height: height
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)

            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = tint.withAlphaComponent(0.55)
            glow.shadowBlurRadius = 6
            glow.shadowOffset = .zero
            glow.set()
            gradient?.draw(in: path, angle: 90)
            NSGraphicsContext.restoreGraphicsState()
        }

        return left + CGFloat(barCount) * (barWidth + barSpacing) - barSpacing + gap
    }

    private func title() -> String {
        switch state {
        case .recording:
            guard let hint, !hint.isEmpty else { return "Слушаю" }
            return "Слушаю · \(hint)"
        case .transcribing:
            // После пары секунд показываем счётчик — видно, что процесс идёт.
            return elapsed >= 2 ? "Расшифровываю \(Int(elapsed)) с" : "Расшифровываю"
        case .error(let message):
            return message
        }
    }

    private static let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.92)
    ]

    /// Ширина, при которой подпись помещается целиком и не болтается пустота.
    func preferredWidth(height: CGFloat) -> CGFloat {
        let bars = CGFloat(barCount) * (barWidth + barSpacing) - barSpacing
        let text = NSAttributedString(string: title(), attributes: Self.titleAttributes).size().width
        return padding + bars + gap + ceil(text) + padding
    }

    private func drawTitle(startingAt x: CGFloat) {
        let string = NSAttributedString(string: title(), attributes: Self.titleAttributes)
        let size = string.size()

        let available = max(bounds.width - x - padding, 0)
        string.draw(in: NSRect(
            x: x,
            y: bounds.midY - size.height / 2,
            width: min(size.width, available),
            height: size.height
        ))
    }
}
