import AppKit
import Foundation

// Фон окна DMG.
//
// Иконки приложения и папки «Программы» сюда не рисуются: их ставит Finder
// по координатам из build.sh, и нарисованная копия оказалась бы рядом
// с настоящей. Здесь только сцена вокруг них.
//
// Предупреждение о первом запуске стоит именно в окне установки, а не только
// в README: без заверения Apple первый запуск macOS блокирует, и человек,
// не читавший README, решит, что программа сломана. Окно установки он
// не прочитать не может.
//
// Рисуется в двойном разрешении и сохраняется как @2x — иначе на Retina фон мыльный.

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/dmg-background"

let width: CGFloat = 620
let height: CGFloat = 430
let scale: CGFloat = 2

/// Куда Finder поставит иконки. Значения повторены в build.sh — держать вместе.
let appIconCenter = CGPoint(x: 165, y: height - 205)
let folderIconCenter = CGPoint(x: 455, y: height - 205)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let violet = rgb(0x6D5BFF)
let cyan = rgb(0x3FD8E8)

/// Смешать два цвета: волна по дороге меняет цвет с голоса на текст.
func blend(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let x = a.usingColorSpace(.sRGB)!, y = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: x.redComponent + (y.redComponent - x.redComponent) * t,
                   green: x.greenComponent + (y.greenComponent - x.greenComponent) * t,
                   blue: x.blueComponent + (y.blueComponent - x.blueComponent) * t,
                   alpha: 0.95)
}

// Рисуем прямо в битмап нужного размера, а не через `lockFocus`: тот берёт
// масштаб у текущего экрана, и на Retina картинка выходит вчетверо больше
// задуманного вместо вдвое.
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.scaleBy(x: scale, y: scale)
context.imageInterpolation = .high

func text(_ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight,
          color: NSColor, align: NSTextAlignment = .center,
          width boxWidth: CGFloat = width, tracking: CGFloat = 0, lineHeight: CGFloat = 0) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    if lineHeight > 0 { style.lineSpacing = lineHeight }
    var attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    if tracking != 0 { attrs[.kern] = tracking }
    let attributed = NSAttributedString(string: string, attributes: attrs)
    let boxHeight = attributed.boundingRect(
        with: NSSize(width: boxWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin]
    ).height
    attributed.draw(with: NSRect(x: point.x, y: point.y - boxHeight,
                                 width: boxWidth, height: boxHeight),
                    options: [.usesLineFragmentOrigin])
}

/// Мягкое цветное пятно.
///
/// Именно `draw(fromCenter:...)`: вариант с прямоугольником обрезает градиент
/// по его границам, и вместо пятна получается светлый квадрат.
func blob(_ center: CGPoint, _ radius: CGFloat, _ color: NSColor, _ alpha: CGFloat) {
    NSGradient(colors: [color.withAlphaComponent(alpha), color.withAlphaComponent(0)])?
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

/// Стеклянная плита — тот же приём, что в интерфейсе самого приложения.
///
/// Настоящего преломления в картинке не сделать, но полупрозрачная заливка,
/// блик по верхней кромке и просвечивающие сквозь неё цветные пятна дают
/// достаточно, чтобы плоскость читалась стеклом. Без блика она выглядит
/// просто серой плашкой.
func glass(_ rect: NSRect, radius: CGFloat) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [rgb(0xFFFFFF, 0.15), rgb(0xFFFFFF, 0.03)])?.draw(in: rect, angle: -90)
    rgb(0xFFFFFF, 0.5).setFill()
    NSBezierPath(roundedRect: NSRect(x: rect.minX + radius * 0.7, y: rect.maxY - 1.4,
                                     width: rect.width - radius * 1.4, height: 1.4),
                 xRadius: 0.7, yRadius: 0.7).fill()
    NSGraphicsContext.restoreGraphicsState()

    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                           xRadius: radius, yRadius: radius)
    rim.lineWidth = 1
    rgb(0xFFFFFF, 0.16).setStroke()
    rim.stroke()
}

// Подложка и цветные пятна: фиолетовое у приложения, бирюзовое у цели.
NSGradient(colors: [rgb(0x161A2B), rgb(0x07080D)])?
    .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)
blob(CGPoint(x: 120, y: height - 120), 300, violet, 0.35)
blob(CGPoint(x: 520, y: 120), 280, cyan, 0.16)

glass(NSRect(x: 48, y: appIconCenter.y - 96, width: width - 96, height: 176), radius: 26)

// Цель размечена цветом: свечение и пунктирное кольцо вокруг папки.
// Стрелки нет намеренно — направление уже задаёт волна, которая от голоса
// слева переходит в цвет цели справа.
blob(folderIconCenter, 90, cyan, 0.30)
let ring = NSBezierPath(ovalIn: NSRect(x: folderIconCenter.x - 74, y: folderIconCenter.y - 74,
                                       width: 148, height: 148))
ring.lineWidth = 1.5
ring.setLineDash([5, 7], count: 2, phase: 0)
cyan.withAlphaComponent(0.55).setStroke()
ring.stroke()

// Волна: голос слева затухает в текст справа — это и есть то, что делает
// программа, и заодно рифмуется со штрихами в самом значке.
let baseY = appIconCenter.y
var x = appIconCenter.x + 80
var barIndex = 0
while x < folderIconCenter.x - 86 {
    let progress = (x - appIconCenter.x - 80) / (folderIconCenter.x - appIconCenter.x - 166)
    let wiggle = abs(sin(Double(barIndex) * 1.1)) + 0.25 * abs(sin(Double(barIndex) * 2.7))
    let barHeight = max(4, CGFloat(wiggle) * 36 * (1 - progress * 0.8) + 4)
    blend(violet, cyan, progress).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: baseY - barHeight / 2, width: 3.5, height: barHeight),
                 xRadius: 1.75, yRadius: 1.75).fill()
    x += 9.5
    barIndex += 1
}

text("SayPer", at: NSPoint(x: 0, y: height - 40), size: 30, weight: .semibold,
     color: .white, tracking: -0.4)
text("Голос становится текстом", at: NSPoint(x: 0, y: height - 84),
     size: 13, weight: .regular, color: rgb(0xFFFFFF, 0.5))

// Низ обычным текстом, без второй стеклянной плашки: два одинаковых предмета
// на одном экране спорят друг с другом, и плита под иконками перестаёт быть
// главной.
text("Перетащи значок в «Программы»", at: NSPoint(x: 0, y: 104),
     size: 13, weight: .semibold, color: .white)
text("Первый запуск macOS заблокирует: Настройки → Конфиденциальность "
     + "и безопасность → «Всё равно открыть»",
     at: NSPoint(x: 80, y: 78), size: 10.5, weight: .regular,
     color: rgb(0xFFFFFF, 0.36), width: width - 160, lineHeight: 2)

NSGraphicsContext.restoreGraphicsState()

// Пиксели вдвое крупнее — размер в точках задаём исходный, иначе Finder
// растянет картинку на всё окно и она поедет.
bitmap.size = NSSize(width: width, height: height)
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }

try png.write(to: URL(fileURLWithPath: "\(outputPath)@2x.png"))
print("\(outputPath)@2x.png")
