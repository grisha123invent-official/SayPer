import AppKit
import SwiftUI

/// Плавающая пилюля: показывает, что микрофон слушает, и что происходит
/// с записью дальше.
///
/// Окно остаётся AppKit — нужна панель, которая висит поверх всего, не
/// перехватывает мышь и не забирает фокус у того приложения, куда человек
/// сейчас диктует. Содержимое — SwiftUI на родном стекле macOS 26.
final class RecordingIndicator {
    enum State: Equatable {
        case recording
        case transcribing
        case error(String)
    }

    private let model = IndicatorModel()
    private var panel: NSPanel?
    private var hideTimer: Timer?

    // MARK: - Публичный интерфейс

    func show(_ state: State) {
        hideTimer?.invalidate()
        hideTimer = nil

        guard Settings.shared.showIndicator else { return }

        let panel = self.panel ?? makePanel()
        model.state = state
        resize(panel, animated: panel.isVisible)
        position(panel)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            model.appear()
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
        model.levelInput = level
    }

    /// Подсказка режима записи рядом с подписью: `nil` — подсказки нет.
    /// В режиме удержания она не нужна, её задаёт «Нажал-нажал».
    func setHint(_ hint: String?) {
        guard hint != model.hint else { return }
        model.hint = hint
        reflow()
    }

    /// Секунды ожидания ответа — чтобы длинная расшифровка не выглядела зависшей.
    func update(elapsed: TimeInterval) {
        model.elapsed = elapsed
        reflow()
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

    // MARK: - Окно

    private func makePanel() -> NSPanel {
        let frame = NSRect(x: 0, y: 0, width: IndicatorMetrics.minWidth, height: IndicatorMetrics.height)

        let hosting = NSHostingView(rootView: IndicatorView(model: model))
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Тень рисует само стекло; своя добавила бы вторую кромку.
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        self.panel = panel
        return panel
    }

    private func reflow() {
        guard let panel, panel.isVisible else { return }
        resize(panel, animated: true)
    }

    private func resize(_ panel: NSPanel, animated: Bool) {
        let width = IndicatorMetrics.width(for: model)
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

// MARK: - Состояние

/// Состояние пилюли. Меняется из AppKit, читается из SwiftUI.
private final class IndicatorModel: ObservableObject {
    @Published var state: RecordingIndicator.State = .recording
    @Published var elapsed: TimeInterval = 0
    @Published var hint: String?
    /// Меняется на каждом кадре звука, поэтому сглаживается здесь,
    /// а не в отрисовке: иначе полоски дёргаются.
    @Published private(set) var level: Float = 0

    private var smoothed: Float = 0

    var levelInput: Float {
        get { smoothed }
        set {
            smoothed = smoothed * 0.55 + newValue * 0.45
            level = smoothed
        }
    }

    /// Однократный импульс появления — по нему SwiftUI играет масштабирование.
    @Published var appearanceToken = 0

    func appear() { appearanceToken &+= 1 }

    var title: String {
        switch state {
        case .recording:
            return hint ?? "Слушаю"
        case .transcribing:
            return elapsed >= 2 ? "Расшифровываю \(Int(elapsed)) с" : "Расшифровываю"
        case .error(let message):
            return message
        }
    }

    var tint: Color {
        switch state {
        case .recording: return Color(red: 0.40, green: 0.68, blue: 1.0)
        case .transcribing: return Color(red: 0.62, green: 0.52, blue: 1.0)
        case .error: return Color(red: 1.0, green: 0.60, blue: 0.40)
        }
    }
}

// MARK: - Размеры

private enum IndicatorMetrics {
    static let height: CGFloat = 38
    static let minWidth: CGFloat = 120
    static let maxWidth: CGFloat = 360
    static let padding: CGFloat = 13
    static let gap: CGFloat = 9
    static let barCount = 5
    static let barWidth: CGFloat = 2.5
    static let barSpacing: CGFloat = 3.5

    static var barsWidth: CGFloat {
        CGFloat(barCount) * (barWidth + barSpacing) - barSpacing
    }

    /// Ширина считается по тексту заранее: панель AppKit должна знать размер
    /// до того, как SwiftUI отрисует содержимое.
    static func width(for model: IndicatorModel) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let text = (model.title as NSString)
            .size(withAttributes: [.font: font])
            .width
        let total = padding + barsWidth + gap + ceil(text) + padding
        return max(minWidth, min(total, maxWidth))
    }
}

// MARK: - Содержимое

private struct IndicatorView: View {
    @ObservedObject var model: IndicatorModel
    @State private var appeared = false

    var body: some View {
        HStack(spacing: IndicatorMetrics.gap) {
            Equalizer(level: model.level, state: model.state, tint: model.tint)
                .frame(width: IndicatorMetrics.barsWidth, height: IndicatorMetrics.height - 18)

            Text(model.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, IndicatorMetrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Родное стекло macOS: подкрашивается под состояние и само добавляет
        // контраст под подписью, поэтому цвет текста остаётся системным.
        .glassEffect(.regular.tint(model.tint.opacity(0.22)), in: Capsule())
        .scaleEffect(appeared ? 1 : 0.92)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: appeared)
        .onAppear { appeared = true }
        .onChange(of: model.appearanceToken) { _, _ in
            appeared = false
            DispatchQueue.main.async { appeared = true }
        }
    }
}

/// Пять полосок: во время записи пляшут по громкости, при расшифровке идёт
/// своя волна, на ошибке замирают.
private struct Equalizer: View {
    let level: Float
    let state: RecordingIndicator.State
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isPaused)) { timeline in
            Canvas { context, size in
                let phase = timeline.date.timeIntervalSinceReferenceDate * 6
                let barWidth = IndicatorMetrics.barWidth
                let spacing = IndicatorMetrics.barSpacing

                for index in 0..<IndicatorMetrics.barCount {
                    let height = max(5, size.height * wave(index: index, phase: phase))
                    let rect = CGRect(
                        x: CGFloat(index) * (barWidth + spacing),
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(tint)
                    )
                }
            }
        }
    }

    private var isPaused: Bool {
        if case .error = state { return true }
        return false
    }

    private func wave(index: Int, phase: Double) -> CGFloat {
        switch state {
        case .recording:
            let amplitude = CGFloat(max(level, 0.06))
            return min(amplitude * (0.5 + 0.5 * abs(sin(phase + Double(index) * 0.8))), 1)
        case .transcribing:
            return 0.22 + 0.5 * abs(sin(phase * 1.2 + Double(index) * 0.75))
        case .error:
            return 0.28
        }
    }
}
