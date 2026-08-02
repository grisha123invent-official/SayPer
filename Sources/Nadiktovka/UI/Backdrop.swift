import AppKit
import SwiftUI

/// Абстрактный фон окна: тёмное поле и светящийся круг звуковой волны.
///
/// Всё медленно живёт: радиус дышит за ~9 секунд (ритм спокойной речи),
/// сам орб едва заметно блуждает за ~33 секунды. При включённом
/// «уменьшении движения» анимация останавливается на нулевой фазе.
struct AmbientGlow: View {
    @Environment(\.colorScheme) private var scheme

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                draw(into: context, size: size, time: time)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func draw(into context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let dark = scheme == .dark

        let base = dark
            ? Color(red: 0.015, green: 0.015, blue: 0.045)
            : Color(red: 0.93, green: 0.93, blue: 0.97)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))

        let breathe = 1 + 0.045 * sin(time * 2 * .pi / 9)
        // Медленное блуждание центра: движение видно боковым зрением,
        // но не отвлекает от текста.
        let wander = time * 2 * .pi / 33
        let shift = CGPoint(x: sin(wander) * 9, y: cos(wander * 0.7) * 7)
        drawOrb(into: context, size: size, scale: breathe, shift: shift, dark: dark)

        // Скрим возвращает контраст тексту на карточках поверх яркого центра.
        let scrim = dark ? Color.black.opacity(0.24) : Color.white.opacity(0.22)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(scrim))
    }

    /// Орб — звуковая волна: тёмное ядро, лавандовое свечение, тёплый отсвет
    /// сверху и расходящиеся кольца-ряби.
    private func drawOrb(into context: GraphicsContext, size: CGSize, scale: Double, shift: CGPoint, dark: Bool) {
        let center = CGPoint(
            x: size.width * 0.5 + shift.x,
            y: size.height * 0.46 + shift.y
        )
        let radius = min(size.width, size.height) * 0.56 * scale

        let body: Gradient
        if dark {
            body = Gradient(stops: [
                .init(color: Color(red: 0.01, green: 0.01, blue: 0.03), location: 0.0),
                .init(color: Color(red: 0.30, green: 0.22, blue: 0.62), location: 0.32),
                .init(color: Color(red: 0.76, green: 0.70, blue: 0.98), location: 0.52),
                .init(color: Color(red: 0.42, green: 0.34, blue: 0.78).opacity(0.42), location: 0.72),
                .init(color: .clear, location: 1.0)
            ])
        } else {
            body = Gradient(stops: [
                .init(color: .white, location: 0.0),
                .init(color: Color(red: 0.78, green: 0.72, blue: 0.99), location: 0.42),
                .init(color: Color(red: 0.58, green: 0.50, blue: 0.92).opacity(0.55), location: 0.68),
                .init(color: .clear, location: 1.0)
            ])
        }

        let orbRect = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )
        context.fill(
            Path(ellipseIn: orbRect),
            with: .radialGradient(body, center: center, startRadius: 0, endRadius: radius)
        )

        // Тёплый отсвет над орбом, как закатная кромка на референсе.
        let warmCenter = CGPoint(x: center.x, y: center.y - radius * 0.62)
        let warm = Gradient(stops: [
            .init(color: Color(red: 1.0, green: 0.72, blue: 0.50).opacity(dark ? 0.30 : 0.38), location: 0),
            .init(color: .clear, location: 1)
        ])
        let warmRadius = radius * 0.66
        context.fill(
            Path(ellipseIn: CGRect(
                x: warmCenter.x - warmRadius, y: warmCenter.y - warmRadius,
                width: warmRadius * 2, height: warmRadius * 2
            )),
            with: .radialGradient(warm, center: warmCenter, startRadius: 0, endRadius: warmRadius)
        )

        // Кольца-ряби, расходящиеся от голоса.
        var rings = context
        rings.addFilter(.blur(radius: 1.5))
        let ringColor = dark
            ? Color(red: 0.76, green: 0.70, blue: 0.98)
            : Color(red: 0.52, green: 0.44, blue: 0.90)
        for ring in 1...4 {
            let ringRadius = radius * (0.34 + CGFloat(ring) * 0.17)
            rings.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - ringRadius, y: center.y - ringRadius,
                    width: ringRadius * 2, height: ringRadius * 2
                )),
                with: .color(ringColor.opacity(dark ? 0.10 : 0.14)),
                lineWidth: 1.2
            )
        }
    }
}

/// Фон панели строки меню: два мягких свечения — сверху и снизу.
///
/// Орб из окна сюда не годится: панель узкая и высокая, его кольцо ложится
/// ровно на список расшифровок, а растянутый до низа орб превращается
/// в общую засветку. Два компактных пятна дают свет там, где он нужен
/// стеклу — у шапки и у кнопок, — оставляя середину спокойной.
struct PanelGlow: View {
    @Environment(\.colorScheme) private var scheme

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 47 : timeline.date.timeIntervalSinceReferenceDate
                draw(&context, size: size, t: t)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let dark = scheme == .dark
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(dark ? Color(red: 0.035, green: 0.03, blue: 0.07)
                              : Color(red: 0.95, green: 0.95, blue: 0.98))
        )

        // Верхнее пятно — под шапкой, нижнее — под кнопками. Дышат в
        // противофазе, поэтому свет медленно перетекает сверху вниз.
        let breatheTop = 1 + 0.10 * sin(t * 2 * .pi / 11)
        let breatheBottom = 1 + 0.10 * sin(t * 2 * .pi / 11 + .pi)

        blob(&context, size: size,
             center: CGPoint(x: size.width * 0.30, y: size.height * 0.06),
             radius: size.width * 0.85 * breatheTop,
             color: dark ? Color(red: 0.42, green: 0.34, blue: 0.86)
                         : Color(red: 0.62, green: 0.58, blue: 0.95),
             alpha: dark ? 0.40 : 0.34)

        blob(&context, size: size,
             center: CGPoint(x: size.width * 0.74, y: size.height * 1.02),
             radius: size.width * 0.80 * breatheBottom,
             color: dark ? Color(red: 0.30, green: 0.38, blue: 0.88)
                         : Color(red: 0.58, green: 0.68, blue: 0.98),
             alpha: dark ? 0.34 : 0.30)
    }

    private func blob(_ context: inout GraphicsContext, size: CGSize,
                      center: CGPoint, radius: CGFloat, color: Color, alpha: Double) {
        let gradient = Gradient(stops: [
            .init(color: color.opacity(alpha), location: 0),
            .init(color: color.opacity(alpha * 0.35), location: 0.45),
            .init(color: .clear, location: 1)
        ])
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2)),
            with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
        )
    }
}
