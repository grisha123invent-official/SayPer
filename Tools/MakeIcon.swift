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

    // Подложка: скруглённый квадрат в пропорциях macOS. Чёрная, а не цветная:
    // фиолетово-синий градиент — самый заезженный фон у AI-приложений,
    // на чёрном знак читается резче и не сливается с соседями в Finder.
    let inset = size * 0.085
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = body.width * 0.2237
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
        NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 1)
    ])
    gradient?.draw(in: shape, angle: -90)

    // Знак: два штриха речи слева, две строки текста справа. Минимум
    // элементов — чтобы в шестнадцати пикселях строки не слипались в пятно.
    NSColor.white.setFill()

    let weight = size * 0.066
    let barGap = weight * 0.85
    let barHeights: [CGFloat] = [0.26, 0.44]
    let lineWidths: [CGFloat] = [0.26, 0.19]
    let bridge = size * 0.055

    let barsWidth = CGFloat(barHeights.count) * weight + CGFloat(barHeights.count - 1) * barGap
    let total = barsWidth + bridge + (lineWidths.max() ?? 0) * size
    let startX = size * 0.5 - total / 2

    for (index, factor) in barHeights.enumerated() {
        let x = startX + CGFloat(index) * (weight + barGap)
        let height = size * factor
        NSBezierPath(
            roundedRect: NSRect(x: x, y: size * 0.5 - height / 2, width: weight, height: height),
            xRadius: weight / 2, yRadius: weight / 2
        ).fill()
    }

    let linesX = startX + barsWidth + bridge
    let block = CGFloat(lineWidths.count) * weight + CGFloat(lineWidths.count - 1) * barGap
    for (index, factor) in lineWidths.enumerated() {
        let y = size * 0.5 + block / 2 - CGFloat(index) * (weight + barGap) - weight
        NSBezierPath(
            roundedRect: NSRect(x: linesX, y: y, width: size * factor, height: weight),
            xRadius: weight / 2, yRadius: weight / 2
        ).fill()
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
