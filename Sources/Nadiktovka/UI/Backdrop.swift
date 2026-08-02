import AppKit
import SwiftUI

/// Сцены фона окна настроек. Выбираются в разделе «Ключ и доступ», карточка
/// «Система». Обе — тихий эмбиент: периоды движения 30–90 секунд, никакого
/// настоящего блюра (только «запечённые» градиенты), при системном
/// «уменьшении движения» кадр замирает.
///
/// Палитры — по итогам ресёрча трендов: зелёно-ледяная гамма вместо
/// индиго-фиолетового штампа, звёзды без соединительных линий.
enum BackdropScene: String, CaseIterable, Identifiable {
    case aurora
    case fluid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "Аврора"
        case .fluid: return "Переливы"
        }
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
        switch self {
        case .aurora: drawAurora(&ctx, size: size, t: t, dark: dark)
        case .fluid: drawFluid(&ctx, size: size, t: t, dark: dark)
        }
    }
}

extension Settings {
    /// Сцена фона окна настроек: ключ `ui.backdrop`.
    var backdropScene: BackdropScene {
        get { BackdropScene(rawValue: text("ui.backdrop")) ?? .fluid }
        set { set(newValue.rawValue, forKey: "ui.backdrop") }
    }
}

/// Фон на уровне окна: занимает всё, включая титлбар с полосой вкладок.
struct AmbientGlow: View {
    @Environment(\.colorScheme) private var scheme
    @State private var scene = Settings.shared.backdropScene

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                // Фиксированная фаза при «уменьшении движения»: статичный
                // кадр из середины дрейфа, а не вырожденный нулевой.
                let t = reduceMotion ? 47 : timeline.date.timeIntervalSinceReferenceDate
                var ctx = context
                scene.draw(&ctx, size: size, t: t, dark: scheme == .dark)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onReceive(
            NotificationCenter.default
                .publisher(for: UserDefaults.didChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            let current = Settings.shared.backdropScene
            if current != scene { scene = current }
        }
    }
}

// MARK: - Шум

private func hash1(_ n: Double) -> Double {
    let s = sin(n * 12.9898 + 78.233) * 43758.5453
    return s - s.rounded(.down)
}

private func hash2(_ x: Double, _ y: Double) -> Double {
    let s = sin(x * 12.9898 + y * 78.233) * 43758.5453
    return s - s.rounded(.down)
}

private func valueNoise(_ x: Double, _ y: Double) -> Double {
    let xi = x.rounded(.down), yi = y.rounded(.down)
    let xf = x - xi, yf = y - yi
    let u = xf * xf * (3 - 2 * xf)
    let v = yf * yf * (3 - 2 * yf)
    let a = hash2(xi, yi), b = hash2(xi + 1, yi)
    let c = hash2(xi, yi + 1), d = hash2(xi + 1, yi + 1)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
}

private func fbm(_ x: Double, _ y: Double) -> Double {
    var total = 0.0, amp = 0.5, fx = x, fy = y
    for _ in 0..<3 {
        total += valueNoise(fx, fy) * amp
        amp *= 0.5; fx *= 2; fy *= 2
    }
    return total
}

private func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
    Color(
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255
    ).opacity(alpha)
}

private func fillBase(_ ctx: inout GraphicsContext, _ size: CGSize, _ color: Color) {
    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
}

/// Скрим возвращает контраст тексту на карточках поверх ярких мест сцены.
private func scrim(_ ctx: inout GraphicsContext, _ size: CGSize, dark: Bool) {
    let c = dark ? Color.black.opacity(0.18) : Color.white.opacity(0.08)
    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c))
}

// MARK: - Общие элементы

/// Редкие одиночные звёзды с медленным мерцанием. Без соединительных линий:
/// паутина «точки-связи» — стоковый штамп.
private func sparseStars(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double,
                         count: Int, alphaScale: Double, color: Color) {
    for i in 0..<count {
        let n = Double(i)
        // Неравномерность: треть звёзд стягивается к двум «гнёздам».
        var x = hash1(n * 3.1) * size.width
        var y = hash1(n * 7.7) * size.height
        if i % 3 == 0 {
            x = x * 0.35 + size.width * 0.68
            y = y * 0.4 + size.height * 0.12
        } else if i % 5 == 0 {
            x = x * 0.3 + size.width * 0.06
            y = y * 0.35 + size.height * 0.55
        }
        let r = 0.7 + hash1(n * 13.3) * 1.6
        let twinkle = 0.55 + 0.45 * sin(t * (0.25 + hash1(n * 5.9) * 0.35) + n)
        let a = (0.25 + hash1(n * 9.4) * 0.55) * twinkle * alphaScale

        ctx.fill(
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
            with: .color(color.opacity(a))
        )
        if r > 1.7 {
            let g = Gradient(stops: [
                .init(color: color.opacity(a * 0.35), location: 0),
                .init(color: .clear, location: 1)
            ])
            let gr = r * 5
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - gr, y: y - gr, width: gr * 2, height: gr * 2)),
                with: .radialGradient(g, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: gr)
            )
        }
    }
}

/// Пучок тонких волн с колокольной огибающей — линии «дышат» в центре
/// и стихают к краям. Мотив голосовой дорожки.
private func drawWaves(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double,
                       color: Color, alphaScale: Double) {
    let lineCount = 7
    let baseY = size.height * 0.72
    for k in 0..<lineCount {
        let n = Double(k)
        let gap = (n - Double(lineCount) / 2) * 9
        let speed = 0.35 * (1 + (hash1(n * 3.7) - 0.5) * 0.4)
        var path = Path()
        var first = true
        var x: CGFloat = 0
        while x <= size.width {
            let dx = Double(x)
            let bell = exp(-pow((dx - Double(size.width) * 0.5) / (Double(size.width) * 0.30), 2))
            let y = baseY + gap + bell * (
                sin(dx * 0.016 + t * speed + n * 0.9) * 16
                    + sin(dx * 0.037 - t * speed * 0.7 + n * 1.7) * 7
            )
            if first { path.move(to: CGPoint(x: x, y: y)); first = false }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
            x += 10
        }
        let central = 1 - abs(n - Double(lineCount) / 2) / (Double(lineCount) / 2)
        ctx.stroke(
            path,
            with: .color(color.opacity((0.10 + central * 0.26) * alphaScale)),
            lineWidth: 0.5 + central * 0.6
        )
    }
}

/// Лента сияния: цепочка мягких свечений вдоль волнистой осевой —
/// обе кромки тают сами собой, «запечённый» блюр вместо настоящего.
private func drawRibbon(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double,
                        hex: UInt32, alpha: Double, baseY: Double, slope: Double,
                        phase: Double, speed: Double, additive: Bool) {
    var layer = ctx
    if additive { layer.blendMode = .plusLighter }

    let step: CGFloat = 30
    var x: CGFloat = -60
    while x <= size.width + 60 {
        let dx = Double(x)
        let cy = baseY
            + dx * slope * 0.35
            + sin(dx * 0.011 + t * speed + phase) * 34
            + (fbm(dx * 0.004 + t * 0.01, phase) - 0.5) * 96
        let h = hash2(dx, phase)
        let rw = 95.0 + h * 50
        let rh = 42.0 + h * 22
        let a = alpha * (0.16 + 0.10 * h)

        let g = Gradient(stops: [
            .init(color: rgb(hex, a), location: 0),
            .init(color: .clear, location: 1)
        ])
        layer.fill(
            Path(ellipseIn: CGRect(x: x - rw, y: cy - rh, width: rw * 2, height: rh * 2)),
            with: .radialGradient(g, center: CGPoint(x: x, y: cy), startRadius: 0, endRadius: rw)
        )
        x += step
    }
}

// MARK: - Сцена «Аврора»

private func drawAurora(_ ctx: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
    if dark {
        fillBase(&ctx, size, rgb(0x04070D))
        let ribbons: [(UInt32, Double, Double, Double)] = [
            (0x34D399, 0.30, size.height * 0.30, -0.10),
            (0x2DD4BF, 0.24, size.height * 0.46, -0.16),
            (0x38BDF8, 0.20, size.height * 0.62, -0.06)
        ]
        for (idx, r) in ribbons.enumerated() {
            drawRibbon(&ctx, size, t: t, hex: r.0, alpha: r.1, baseY: r.2, slope: r.3,
                       phase: Double(idx) * 1.7, speed: 0.05 + Double(idx) * 0.018,
                       additive: true)
        }
        sparseStars(&ctx, size, t: t, count: 22, alphaScale: 0.8, color: .white)
    } else {
        // Аврора на светлом — пастельные ленты на почти белом: классическая
        // тёмная схема на светлой базе не работает.
        fillBase(&ctx, size, rgb(0xF3F6FB))
        let ribbons: [(UInt32, Double, Double, Double)] = [
            (0x34D399, 0.42, size.height * 0.30, -0.10),
            (0x2DD4BF, 0.36, size.height * 0.46, -0.16),
            (0x60A5FA, 0.30, size.height * 0.62, -0.06)
        ]
        for (idx, r) in ribbons.enumerated() {
            drawRibbon(&ctx, size, t: t, hex: r.0, alpha: r.1, baseY: r.2, slope: r.3,
                       phase: Double(idx) * 1.7, speed: 0.05 + Double(idx) * 0.018,
                       additive: false)
        }
    }
    scrim(&ctx, size, dark: dark)
}

// MARK: - Сцена «Переливы»

private func drawFluid(_ ctx: inout GraphicsContext, size: CGSize, t: Double, dark: Bool) {
    let blobs: [(UInt32, Double, Double, Double, Double)] = dark
        ? [
            (0x2DD4BF, 0.22, 0.28, 0.58, 0.34),
            (0x38BDF8, 0.62, 0.20, 0.52, 0.30),
            (0x3B82F6, 0.80, 0.62, 0.60, 0.26),
            (0x22D3EE, 0.35, 0.78, 0.48, 0.26),
            (0xE879F9, 0.58, 0.50, 0.24, 0.16)
        ]
        : [
            (0x6EE7B7, 0.22, 0.28, 0.58, 0.50),
            (0x7DD3FC, 0.62, 0.20, 0.52, 0.50),
            (0xA5B4FC, 0.80, 0.62, 0.60, 0.40),
            (0x99F6E4, 0.35, 0.78, 0.48, 0.42),
            (0xF9A8D4, 0.58, 0.50, 0.24, 0.26)
        ]

    fillBase(&ctx, size, dark ? rgb(0x05070C) : rgb(0xF3F5FA))

    for (idx, blob) in blobs.enumerated() {
        let (hex, cx, cy, radius, alpha) = blob
        let n = Double(idx)
        // Лиссажу-дрейф: несоизмеримые периоды, траектория не повторяется.
        let dx = sin(t * (0.05 + hash1(n) * 0.03) + n * 2.1) * size.width * 0.05
        let dy = sin(t * (0.04 + hash1(n * 2.2) * 0.03) + n * 1.3) * size.height * 0.05
        let r = min(size.width, size.height) * radius
        let c = CGPoint(x: size.width * cx + dx, y: size.height * cy + dy)
        let g = Gradient(stops: [
            .init(color: rgb(hex, alpha), location: 0),
            .init(color: .clear, location: 1)
        ])
        var layer = ctx
        if dark { layer.blendMode = .plusLighter }
        layer.fill(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(g, center: c, startRadius: 0, endRadius: r)
        )
    }

    drawWaves(&ctx, size, t: t,
              color: dark ? rgb(0xA5F3FC) : rgb(0x475569),
              alphaScale: dark ? 1.0 : 0.8)
    scrim(&ctx, size, dark: dark)
}
