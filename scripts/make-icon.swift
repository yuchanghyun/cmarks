// 앱 아이콘 생성. 실행: make icon
// cmux 아이콘처럼 밝은 유리 바탕 위에 파란 계열 그라데이션(하늘색 → 파랑 → 남색)의 둥근 "c"를 그려
// AppIcon.appiconset의 PNG 10장을 만든다.
//   swift scripts/make-icon.swift [출력 폴더] [--variant glass|blue] [--preview 파일.png]
// glass(기본): cmux처럼 밝은 바탕 + 그라데이션 c. blue: 파란 그라데이션 바탕 + 흰 c.
import AppKit

var args = Array(CommandLine.arguments.dropFirst())
var variant = "glass"
var preview: String?
if let i = args.firstIndex(of: "--variant") { variant = args[i + 1]; args.removeSubrange(i...(i + 1)) }
if let i = args.firstIndex(of: "--preview") { preview = args[i + 1]; args.removeSubrange(i...(i + 1)) }
let outDir = args.first ?? "App/Resources/Assets.xcassets/AppIcon.appiconset"

let specs: [(file: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// cmux 아이콘에서 표본화한 색: 왼쪽 위 하늘색 → 가운데 파랑 → 오른쪽 아래 남색
let cmuxGradient = NSGradient(colorsAndLocations: (rgb(0x66D8FC), 0), (rgb(0x4A97F4), 0.55), (rgb(0x4A5BEF), 1))!

func glyphPath(_ font: NSFont, _ character: Character) -> NSBezierPath {
    var utf16 = Array(String(character).utf16)
    var glyph = CGGlyph()
    CTFontGetGlyphsForCharacters(font as CTFont, &utf16, &glyph, 1)
    let cg = CTFontCreatePathForGlyph(font as CTFont, glyph, nil)!
    return NSBezierPath(cgPath: cg)
}

func render(px: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap rep") }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.setAllowsAntialiasing(true)
    ctx.cgContext.interpolationQuality = .high
    defer { NSGraphicsContext.restoreGraphicsState() }

    let side = CGFloat(px)
    let inset = side * 0.09 // macOS 아이콘 그리드 여백
    let square = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = square.width * 0.2237
    let shape = NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius)

    // 글자: 둥근 SF 굵은 c
    let descriptor = NSFont.systemFont(ofSize: square.height * 0.72, weight: .heavy).fontDescriptor.withDesign(.rounded)!
    let font = NSFont(descriptor: descriptor, size: square.height * 0.72)!
    let glyph = glyphPath(font, "c")
    let bounds = glyph.bounds
    let transform = AffineTransform(translationByX: square.midX - bounds.midX, byY: square.midY - bounds.midY)
    glyph.transform(using: transform)

    if variant == "glass" {
        // cmux처럼 밝은 바탕에 그라데이션 글자
        NSGradient(starting: rgb(0xFDFDFD), ending: rgb(0xE9E9EB))!.draw(in: shape, angle: -90)
        NSGraphicsContext.current?.saveGraphicsState()
        shape.addClip()
        let rim = NSBezierPath(roundedRect: square.insetBy(dx: side * 0.004, dy: side * 0.004), xRadius: radius, yRadius: radius)
        rim.lineWidth = side * 0.008
        rgb(0x000000, 0.06).setStroke(); rim.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = rgb(0x2F6BEA, 0.35)
        shadow.shadowBlurRadius = side * 0.03
        shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        rgb(0x4A97F4).setFill(); glyph.fill() // 그림자 형태를 만들기 위한 기본 채움
        NSGraphicsContext.current?.restoreGraphicsState()
        cmuxGradient.draw(in: glyph, angle: -35)
    } else {
        // 파란 그라데이션 바탕 + 흰 c
        cmuxGradient.draw(in: shape, angle: -35)
        NSGraphicsContext.current?.saveGraphicsState()
        shape.addClip()
        // 위쪽 은은한 하이라이트
        let top = NSRect(x: square.minX, y: square.midY, width: square.width, height: square.height / 2)
        NSGradient(starting: rgb(0xFFFFFF, 0.0), ending: rgb(0xFFFFFF, 0.16))!.draw(in: top, angle: 90)
        NSGraphicsContext.current?.restoreGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = rgb(0x0B2A7A, 0.35)
        shadow.shadowBlurRadius = side * 0.025
        shadow.shadowOffset = NSSize(width: 0, height: -side * 0.01)
        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill(); glyph.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return png
}

if let preview {
    try render(px: 1024).write(to: URL(fileURLWithPath: preview))
    print("wrote preview \(preview) (\(variant))")
} else {
    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    for spec in specs {
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(spec.file)
        try render(px: spec.px).write(to: url)
    }
    print("wrote \(specs.count) icons to \(outDir) (\(variant))")
}
