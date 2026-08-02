import AppKit
import Foundation

// Фон окна DMG: подсказка «перетащи сюда» и предупреждение о первом запуске.
//
// Предупреждение стоит именно здесь, а не только в README: без подписи Apple
// первый запуск macOS блокирует, и человек, не прочитавший README, решит,
// что программа сломана. Окно установки он не прочитать не может.
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
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
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

// Подложка: почти чёрная с холодным подсветом сверху — под цвет иконки.
NSGradient(colors: [rgb(0x1A1A20), rgb(0x0B0B0E)])?
    .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

// Мягкое пятно за иконкой приложения: взгляд идёт слева направо, и начинать
// он должен с того, что перетаскивают.
// Именно `draw(fromCenter:...)`: вариант с прямоугольником обрезает
// градиент по его границам, и вместо пятна получается светлый квадрат.
let glowRadius: CGFloat = 210
NSGradient(colors: [rgb(0x6D5BFF, 0.22), rgb(0x6D5BFF, 0)])?.draw(
    fromCenter: appIconCenter, radius: 0,
    toCenter: appIconCenter, radius: glowRadius,
    options: []
)

func draw(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight,
          color: NSColor, align: NSTextAlignment = .center, width boxWidth: CGFloat = width) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    let attributed = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style
    ])
    let height = attributed.boundingRect(
        with: NSSize(width: boxWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin]
    ).height
    attributed.draw(with: NSRect(x: point.x, y: point.y - height, width: boxWidth, height: height),
                    options: [.usesLineFragmentOrigin])
}

draw("SayPer", at: NSPoint(x: 0, y: height - 46), size: 26, weight: .semibold, color: .white)
draw("Перетащи значок в «Программы»", at: NSPoint(x: 0, y: height - 78),
     size: 13, weight: .regular, color: rgb(0xFFFFFF, 0.55))

// Стрелка между иконками. Рисуется от края одной подписи до края другой,
// чтобы не лезть под текст под иконками.
let arrowY = appIconCenter.y
let arrowStart = appIconCenter.x + 92
let arrowEnd = folderIconCenter.x - 92

let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: arrowStart, y: arrowY))
shaft.line(to: NSPoint(x: arrowEnd - 12, y: arrowY))
shaft.lineWidth = 2
shaft.lineCapStyle = .round
rgb(0xFFFFFF, 0.30).setStroke()
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: arrowEnd - 16, y: arrowY + 7))
head.line(to: NSPoint(x: arrowEnd, y: arrowY))
head.line(to: NSPoint(x: arrowEnd - 16, y: arrowY - 7))
head.lineWidth = 2
head.lineCapStyle = .round
head.lineJoinStyle = .round
rgb(0xFFFFFF, 0.45).setStroke()
head.stroke()

// Плашка с предупреждением о первом запуске — внизу, во всю ширину.
let noticeRect = NSRect(x: 40, y: 28, width: width - 80, height: 74)
let noticePath = NSBezierPath(roundedRect: noticeRect, xRadius: 12, yRadius: 12)
rgb(0xFFFFFF, 0.05).setFill()
noticePath.fill()
rgb(0xFFB35C, 0.30).setStroke()
noticePath.lineWidth = 1
noticePath.stroke()

draw("Первый запуск macOS заблокирует", at: NSPoint(x: noticeRect.minX + 18, y: noticeRect.maxY - 14),
     size: 12, weight: .semibold, color: rgb(0xFFB35C), align: .left,
     width: noticeRect.width - 36)
draw("""
     Приложение подписано, но не заверено Apple. Открой Системные настройки → \
     Конфиденциальность и безопасность и нажми «Всё равно открыть».
     """,
     at: NSPoint(x: noticeRect.minX + 18, y: noticeRect.maxY - 34),
     size: 11.5, weight: .regular, color: rgb(0xFFFFFF, 0.52), align: .left,
     width: noticeRect.width - 36)

NSGraphicsContext.restoreGraphicsState()

// Пиксели вдвое крупнее — размер в точках задаём исходный, иначе Finder
// растянет картинку на всё окно и она поедет.
bitmap.size = NSSize(width: width, height: height)
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }

try png.write(to: URL(fileURLWithPath: "\(outputPath)@2x.png"))
print("\(outputPath)@2x.png")
