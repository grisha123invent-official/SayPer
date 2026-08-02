import AppKit
import Foundation

// Рисует иконку приложения и раскладывает её в .iconset.
// Запуск: swift Tools/MakeIcon.swift <путь к .iconset>

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/AppIcon.iconset"

/// Один слой иконки нужного размера в пикселях.
func render(size: CGFloat) -> Data? {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Подложка: скруглённый квадрат в пропорциях macOS.
    let inset = size * 0.085
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = body.width * 0.2237
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.42, green: 0.31, blue: 0.93, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.44, blue: 0.94, alpha: 1)
    ])
    gradient?.draw(in: shape, angle: -90)

    // Знак: слева вертикальные штрихи речи, справа они ложатся строками
    // текста. Микрофона нет намеренно — он про начало пути, а иконка
    // должна показывать превращение: сказал, распозналось, вставилось.
    NSColor.white.setFill()

    let barWidth = size * 0.052
    let barGap = size * 0.045
    let barHeights: [CGFloat] = [0.20, 0.38, 0.28, 0.46]
    for (index, factor) in barHeights.enumerated() {
        let x = size * 0.20 + CGFloat(index) * (barWidth + barGap)
        let height = size * factor
        let rect = NSRect(x: x, y: size * 0.5 - height / 2, width: barWidth, height: height)
        NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }

    let lineHeight = size * 0.052
    let lineGap = size * 0.045
    let lineWidths: [CGFloat] = [0.25, 0.19, 0.23]
    for (index, factor) in lineWidths.enumerated() {
        let y = size * 0.5 + (lineHeight + lineGap) - CGFloat(index) * (lineHeight + lineGap) - lineHeight / 2
        let rect = NSRect(x: size * 0.55, y: y, width: size * factor, height: lineHeight)
        NSBezierPath(roundedRect: rect, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let sizes: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

let directory = URL(fileURLWithPath: outputPath)
try? FileManager.default.removeItem(at: directory)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for (name, pixels) in sizes {
    guard let data = render(size: pixels) else {
        FileHandle.standardError.write(Data("Не удалось нарисовать \(name)\n".utf8))
        exit(1)
    }
    try data.write(to: directory.appendingPathComponent(name))
}

print("Иконка: \(outputPath)")
