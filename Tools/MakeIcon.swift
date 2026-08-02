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

    // Микрофон по центру.
    NSColor.white.setFill()
    NSColor.white.setStroke()

    let capsuleWidth = size * 0.155
    let capsule = NSRect(
        x: size * 0.5 - capsuleWidth / 2,
        y: size * 0.42,
        width: capsuleWidth,
        height: size * 0.30
    )
    NSBezierPath(roundedRect: capsule, xRadius: capsuleWidth / 2, yRadius: capsuleWidth / 2).fill()

    let arc = NSBezierPath()
    arc.lineWidth = size * 0.038
    arc.lineCapStyle = .round
    arc.appendArc(
        withCenter: NSPoint(x: size * 0.5, y: size * 0.48),
        radius: size * 0.145,
        startAngle: 200,
        endAngle: 340,
        clockwise: true
    )
    arc.stroke()

    let stemWidth = size * 0.038
    let stem = NSRect(
        x: size * 0.5 - stemWidth / 2,
        y: size * 0.285,
        width: stemWidth,
        height: size * 0.06
    )
    NSBezierPath(rect: stem).fill()

    let baseWidth = size * 0.185
    let base = NSRect(
        x: size * 0.5 - baseWidth / 2,
        y: size * 0.258,
        width: baseWidth,
        height: size * 0.038
    )
    NSBezierPath(roundedRect: base, xRadius: size * 0.019, yRadius: size * 0.019).fill()

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
