// Draws Resources/AppIcon.icns: a graphite squircle with the SF Symbols gauge.
import AppKit

let output = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: an 824/1024 body, centered, with a continuous ~22.5% corner radius.
    let inset = size * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = body.width * 0.225
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    NSGraphicsContext.current?.cgContext.setShadow(
        offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03,
        color: NSColor.black.withAlphaComponent(0.35).cgColor
    )
    NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    NSGradient(colors: [
        NSColor(calibratedRed: 0.30, green: 0.31, blue: 0.34, alpha: 1),
        NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1),
    ])!.draw(in: path, angle: -90)

    NSColor.white.withAlphaComponent(0.14).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: size * 0.002, dy: size * 0.002), xRadius: radius, yRadius: radius)
    rim.lineWidth = max(1, size * 0.004)
    rim.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
