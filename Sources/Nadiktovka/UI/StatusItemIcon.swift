import AppKit

/// Значок в строке меню — тот же знак, что на иконке приложения: два штриха
/// речи слева, две строки текста справа.
///
/// Системный микрофон заменён своим знаком, чтобы приложение узнавалось
/// в строке меню, где у соседей тоже микрофоны и волны.
///
/// Картинка помечена как template: в этом режиме macOS сама красит её под
/// светлую и тёмную строку меню и под нажатие. Свой цвет задаётся отдельно —
/// `contentTintColor` у кнопки, — и работает поверх шаблона.
enum StatusItemIcon {
    /// Высота значка. 18 — стандарт строки меню; знак внутри ещё уже,
    /// иначе он упирается в соседей.
    private static let side: CGFloat = 18

    /// Толщина штриха. Меньше двух точек — на не-Retina знак рассыпается.
    private static let weight: CGFloat = 2
    private static let gap: CGFloat = 1.8
    /// Просвет между штрихами речи и строками текста.
    private static let bridge: CGFloat = 2.2

    /// Высоты штрихов в покое и длины строк — пропорции взяты с иконки.
    private static let restingBars: [CGFloat] = [6.5, 11]
    private static let lineWidths: [CGFloat] = [6.5, 4.8]

    /// Знак в покое.
    static func idle() -> NSImage { make(bars: restingBars) }

    /// Знак во время записи: штрихи растут с громкостью.
    ///
    /// Отличать состояния одним цветом мало — цвет не единственный носитель
    /// смысла. Здесь меняется сама форма, и заодно видно, что микрофон слышит
    /// голос, а не просто включён.
    static func recording(level: Float) -> NSImage {
        let amplitude = CGFloat(min(max(level, 0), 1))
        let bars = restingBars.map { base -> CGFloat in
            // От почти покоя до почти всей высоты значка: в тишине штрихи
            // не должны оказаться ниже, чем в покое, — запись не выглядит
            // слабее бездействия.
            min(base * (0.95 + amplitude * 0.55), side - 3)
        }
        return make(bars: bars)
    }

    /// Знак во время расшифровки: штрихи выровнены — говорить уже не нужно.
    static func transcribing() -> NSImage { make(bars: [9, 9]) }

    private static func make(bars: [CGFloat]) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            NSColor.black.setFill()

            let barsWidth = CGFloat(bars.count) * weight + CGFloat(bars.count - 1) * gap
            let linesWidth = lineWidths.max() ?? 0
            let startX = (side - (barsWidth + bridge + linesWidth)) / 2

            for (index, height) in bars.enumerated() {
                let x = startX + CGFloat(index) * (weight + gap)
                NSBezierPath(
                    roundedRect: NSRect(x: x, y: (side - height) / 2, width: weight, height: height),
                    xRadius: weight / 2, yRadius: weight / 2
                ).fill()
            }

            let linesX = startX + barsWidth + bridge
            let block = CGFloat(lineWidths.count) * weight + CGFloat(lineWidths.count - 1) * gap
            for (index, width) in lineWidths.enumerated() {
                let y = side / 2 + block / 2 - CGFloat(index) * (weight + gap) - weight
                NSBezierPath(
                    roundedRect: NSRect(x: linesX, y: y, width: width, height: weight),
                    xRadius: weight / 2, yRadius: weight / 2
                ).fill()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}
