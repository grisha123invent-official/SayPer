import AppKit
import SwiftUI

/// Плавающая пилюля: показывает, что микрофон слушает, и что происходит
/// с записью дальше.
///
/// Окно остаётся AppKit — нужна панель, которая висит поверх всего, не
/// перехватывает мышь и не забирает фокус у того приложения, куда человек
/// сейчас диктует.
///
/// Стекло — `NSGlassEffectView` из macOS 26 в прозрачном стиле: настоящее
/// преломление того, что за окном, то есть чужого приложения, куда диктуют.
/// Ни `glassEffect` из SwiftUI, ни `NSVisualEffectView` тут не подошли:
/// первый преломлял пустоту внутри прозрачного окна и выдавал серую плашку,
/// второй давал матовую, но глухую подложку. Оформление у стекла принудительно
/// тёмное: пилюля висит над чужими окнами, и её читаемость не должна зависеть
/// от того, какую тему человек выбрал приложению.
final class RecordingIndicator {
    enum State: Equatable {
        case recording
        case transcribing
        case error(String)
    }

    private let model = IndicatorModel()
    private var panel: NSPanel?
    private var glass: NSGlassEffectView?
    private var hideTimer: Timer?

    // MARK: - Публичный интерфейс

    func show(_ state: State) {
        hideTimer?.invalidate()
        hideTimer = nil

        guard Settings.shared.showIndicator else { return }

        let panel = self.panel ?? makePanel()
        model.state = state
        model.startRim()
        // Прозрачное стекло само по себе бесцветно — состояние в нём читается
        // только через тон.
        glass?.tintColor = NSColor(model.tint).withAlphaComponent(0.20)
        resize(panel, animated: panel.isVisible)
        position(panel)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
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
        }, completionHandler: { [weak self, weak panel] in
            panel?.orderOut(nil)
            self?.model.stopRim()
        })
    }

    // MARK: - Окно

    private func makePanel() -> NSPanel {
        let bleed = IndicatorMetrics.bleed
        let frame = NSRect(
            x: 0, y: 0,
            width: IndicatorMetrics.minWidth + bleed * 2,
            height: IndicatorMetrics.height + bleed * 2
        )

        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]

        // Порядок добавления — порядок слоёв. Свечение уходит под стекло,
        // чтобы оно его преломляло, а обводка и текст ложатся поверх.
        let halo = NSHostingView(rootView: IndicatorHalo(model: model))
        halo.frame = frame
        halo.autoresizingMask = [.width, .height]
        container.addSubview(halo)

        let glass = NSGlassEffectView(frame: frame.insetBy(dx: bleed, dy: bleed))
        glass.style = .clear
        glass.cornerRadius = IndicatorMetrics.height / 2
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.autoresizingMask = [.width, .height]
        // Полоски и подпись живут внутри стекла: класс гарантирует правильный
        // порядок слоёв только для `contentView`, произвольные подвиды могут
        // оказаться где угодно.
        glass.contentView = NSHostingView(rootView: IndicatorContent(model: model))
        container.addSubview(glass)
        self.glass = glass

        // Кромка — снаружи стекла, отдельным слоем: внутри её бы преломило
        // вместе с содержимым, и искры размазало бы по краю.
        let rim = NSHostingView(rootView: IndicatorRim(model: model))
        rim.frame = frame
        rim.autoresizingMask = [.width, .height]
        container.addSubview(rim)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = container
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
        let width = IndicatorMetrics.width(for: model) + IndicatorMetrics.bleed * 2
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
            // Минус припуск: сама пилюля должна остаться там же, где была,
            // а выросло вокруг неё только поле для свечения.
            y: visible.minY + 96 - IndicatorMetrics.bleed
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

    /// Уровень для картинки — сглажен куда сильнее, чем для полосок.
    /// Полоскам нужна быстрая реакция, свечению и скорости искр — нет:
    /// на голосовом сигнале они начинали полыхать и дёргаться.
    @Published private(set) var calmLevel: Float = 0

    private var smoothed: Float = 0
    private var calm: Float = 0

    var levelInput: Float {
        get { smoothed }
        set {
            smoothed = smoothed * 0.55 + newValue * 0.45
            level = smoothed
            calm = calm * 0.90 + newValue * 0.10
            calmLevel = calm
        }
    }

    /// Пройденная искрой доля контура, 0…1.
    ///
    /// Копится по шагам, а не считается из абсолютного времени. Формула
    /// `время × скорость` при меняющейся скорости давала скачки на пол-контура
    /// каждый кадр: время с 2001 года — сотни миллионов секунд, и любое
    /// изменение множителя швыряло искру куда попало. Это и было мерцание.
    @Published private(set) var rimPhase: Double = 0

    private var ticker: Timer?

    func startRim() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard !self.isStatic else { return }
            self.rimPhase = (self.rimPhase + self.runnerSpeed / 360 / 30)
                .truncatingRemainder(dividingBy: 1)
        }
    }

    func stopRim() {
        ticker?.invalidate()
        ticker = nil
    }

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
        case .transcribing: return Palette.accent
        case .error: return Color(red: 1.0, green: 0.60, blue: 0.40)
        }
    }

    /// На ошибке всё замирает: мигающая ошибка читается хуже неподвижной.
    var isStatic: Bool {
        if case .error = state { return true }
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Градусов в секунду для бегущей по контуру искры.
    var runnerSpeed: Double {
        switch state {
        case .recording: return 62 + Double(min(calmLevel, 1)) * 48
        case .transcribing: return 115
        case .error: return 0
        }
    }
}

// MARK: - Размеры

private enum IndicatorMetrics {
    static let height: CGFloat = 30
    static let minWidth: CGFloat = 104
    static let maxWidth: CGFloat = 320
    static let padding: CGFloat = 11
    static let gap: CGFloat = 8
    static let barCount = 5
    static let barWidth: CGFloat = 2
    static let barSpacing: CGFloat = 3
    /// Поле вокруг пилюли под свечение: окно больше самой капсулы на столько
    /// с каждой стороны.
    static let bleed: CGFloat = 14
    static let font = NSFont.systemFont(ofSize: 11, weight: .medium)

    static var barsWidth: CGFloat {
        CGFloat(barCount) * (barWidth + barSpacing) - barSpacing
    }

    /// Ширина считается по тексту заранее: панель AppKit должна знать размер
    /// до того, как SwiftUI отрисует содержимое.
    static func width(for model: IndicatorModel) -> CGFloat {
        let text = (model.title as NSString)
            .size(withAttributes: [.font: font])
            .width
        let total = padding + barsWidth + gap + ceil(text) + padding
        return max(minWidth, min(total, maxWidth))
    }
}

// MARK: - Свечение под стеклом

/// Мягкий ореол в цвет состояния. Лежит под стеклом, поэтому стекло его
/// размывает и подкрашивается им изнутри — тонировать стекло отдельно не надо.
private struct IndicatorHalo: View {
    @ObservedObject var model: IndicatorModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: model.isStatic)) { timeline in
            let t = model.isStatic ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Capsule()
                    .fill(model.tint)
                    .padding(IndicatorMetrics.bleed)
                    .blur(radius: 13)
                    .opacity(opacity(at: t))

                // Тёмная подложка ровно под капсулой. Прозрачное стекло само
                // подстраивается под фон и над белым документом остаётся белым —
                // светлая подпись на нём пропадает. Подложка лежит под стеклом,
                // поэтому стекло её преломляет вместе с фоном: пилюля остаётся
                // стеклянной, но подпись читается на любом окне.
                Capsule()
                    .fill(Color.black.opacity(0.34))
                    .padding(IndicatorMetrics.bleed)
            }
        }
        .allowsHitTesting(false)
    }

    /// Во время записи ореол дышит по громкости — свет отзывается на голос,
    /// а не живёт своим ритмом. При расшифровке дыхание ровное.
    private func opacity(at time: TimeInterval) -> Double {
        switch model.state {
        case .recording:
            return 0.42 + Double(min(model.calmLevel, 1)) * 0.26
        case .transcribing:
            return 0.50 + 0.14 * sin(time * 2 * .pi / 2.4)
        case .error:
            return 0.58
        }
    }
}

// MARK: - Содержимое

/// Содержимое пилюли — то, что лежит внутри стекла.
private struct IndicatorContent: View {
    @ObservedObject var model: IndicatorModel

    var body: some View {
        HStack(spacing: IndicatorMetrics.gap) {
            Equalizer(level: model.level, state: model.state, tint: model.tint)
                .frame(width: IndicatorMetrics.barsWidth, height: 12)

            Text(model.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, IndicatorMetrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Кромка капсулы: ровный светлый волосок плюс две искры, бегущие по нему
/// навстречу друг другу. Скорость искр зависит от состояния — во время
/// записи она растёт с громкостью, и контур отзывается на голос.
private struct IndicatorRim: View {
    @ObservedObject var model: IndicatorModel

    var body: some View {
        // Доля пути, а не угол: `trim` идёт по длине контура, поэтому искра
        // проходит прямые участки и закругления с одной скоростью. Угловой
        // градиент так не умеет — на вытянутой капсуле он летел по бокам
        // и полз на торцах.
        ZStack {
            Capsule()
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)

            if !model.isStatic {
                runner(at: model.rimPhase)
                runner(at: model.rimPhase + 0.5)
            }
        }
        .padding(IndicatorMetrics.bleed)
        .allowsHitTesting(false)
    }

    /// Искра с хвостом: три дуги от длинной тусклой к короткой яркой.
    /// Градиент вдоль обрезанного контура SwiftUI не рисует, а наложение
    /// трёх дуг даёт тот же комет-эффект без своей геометрии.
    private func runner(at progress: Double) -> some View {
        ZStack {
            arc(from: progress - 0.16, to: progress, color: model.tint.opacity(0.22), width: 1.4, blur: 1.6)
            arc(from: progress - 0.06, to: progress, color: model.tint.opacity(0.70), width: 1.4, blur: 0.9)
            arc(from: progress - 0.015, to: progress, color: .white.opacity(0.95), width: 1.5, blur: 0.5)
        }
    }

    private func arc(from: Double, to: Double, color: Color, width: CGFloat, blur: CGFloat) -> some View {
        // `trim` не умеет через ноль: дуга, начавшаяся до конца контура,
        // рисуется двумя кусками — хвостом в конце и головой в начале.
        let head = to.truncatingRemainder(dividingBy: 1)
        let tail = from < 0 ? from + 1 : from

        return ZStack {
            if tail > head {
                segment(tail, 1, color, width, blur)
                segment(0, head, color, width, blur)
            } else {
                segment(tail, head, color, width, blur)
            }
        }
    }

    private func segment(_ from: Double, _ to: Double, _ color: Color,
                         _ width: CGFloat, _ blur: CGFloat) -> some View {
        Capsule()
            .inset(by: width / 2)
            .trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            // Небольшое размытие превращает штрих в свечение: резкая линия
            // на матовом стекле выглядит наклейкой.
            .blur(radius: blur)
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
                    let height = max(4, size.height * wave(index: index, phase: phase))
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
