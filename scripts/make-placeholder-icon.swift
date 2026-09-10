// 임시 앱 아이콘 생성. 실행: make icon
// 파란 라운드 사각형 위에 "c" 글자를 그려 AppIcon.appiconset의 PNG 10장을 만든다.
import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? "App/Resources/Assets.xcassets/AppIcon.appiconset"
let specs: [(file: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func render(px: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap rep") }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let side = CGFloat(px)
    let inset = side * 0.09 // macOS 아이콘 그리드 여백
    let square = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = square.width * 0.2237
    let path = NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.96, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.60, alpha: 1)
    )!
    gradient.draw(in: path, angle: -90)

    let font = NSFont.systemFont(ofSize: square.height * 0.68, weight: .bold)
    let text = NSAttributedString(string: "c", attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = text.size()
    text.draw(at: NSPoint(x: square.midX - size.width / 2, y: square.midY - size.height / 2 + square.height * 0.03))

    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return png
}

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for spec in specs {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(spec.file)
    try render(px: spec.px).write(to: url)
}
print("wrote \(specs.count) icons to \(outDir)")
