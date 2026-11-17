#!/usr/bin/env swift
// Draws the zzPic app icon with Core Graphics and produces AppIcon.icns (+ a PNG preview).
// Usage: swift Scripts/make-icon.swift Resources/AppIcon.icns docs/icon.png
import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: make-icon.swift <out.icns> [preview.png]")
    exit(1)
}
let icnsPath = arguments[1]
let previewPath = arguments.count > 2 ? arguments[2] : nil

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// Apple-style "squircle" (superellipse) used by macOS app icons.
func squircle(_ rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * copysign(pow(abs(c), 2 / n), c)
        let y = rect.midY + b * copysign(pow(abs(s), 2 / n), s)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func linearGradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint, locations: [CGFloat]? = nil) {
    let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// A photo print: white card with a little landscape inside.
func drawPhoto(_ ctx: CGContext, center: CGPoint, size: CGSize, angle: CGFloat, faded: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let card = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    let cardPath = CGPath(roundedRect: card, cornerWidth: 34, cornerHeight: 34, transform: nil)

    // Card + shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0x1B0B4A, faded ? 0.25 : 0.45))
    ctx.addPath(cardPath)
    ctx.setFillColor(color(0xFFFFFF, faded ? 0.55 : 1))
    ctx.fillPath()
    ctx.restoreGState()

    if !faded {
        // Picture area.
        let inset: CGFloat = 26
        let photo = card.insetBy(dx: inset, dy: inset)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: photo, cornerWidth: 14, cornerHeight: 14, transform: nil))
        ctx.clip()

        // Sky.
        linearGradient(ctx, [color(0x4FB4FF), color(0xA7DCFF), color(0xFFE3B8)],
                       from: CGPoint(x: 0, y: photo.maxY), to: CGPoint(x: 0, y: photo.minY),
                       locations: [0, 0.6, 1])

        // Sun with glow.
        let sun = CGPoint(x: photo.minX + photo.width * 0.70, y: photo.minY + photo.height * 0.66)
        let glow = CGGradient(colorsSpace: sRGB, colors: [color(0xFFF6C8, 0.9), color(0xFFF6C8, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: 120, options: [])
        ctx.setFillColor(color(0xFFD23F))
        ctx.fillEllipse(in: CGRect(x: sun.x - 44, y: sun.y - 44, width: 88, height: 88))

        // Mountains: a zig-zag ridge (a wink to the "zz").
        func ridge(_ points: [(CGFloat, CGFloat)], _ top: CGColor, _ bottom: CGColor) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: photo.minX - 10, y: photo.minY - 10))
            for (fx, fy) in points {
                path.addLine(to: CGPoint(x: photo.minX + photo.width * fx, y: photo.minY + photo.height * fy))
            }
            path.addLine(to: CGPoint(x: photo.maxX + 10, y: photo.minY - 10))
            path.closeSubpath()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            linearGradient(ctx, [top, bottom], from: CGPoint(x: 0, y: photo.maxY * 0.4), to: CGPoint(x: 0, y: photo.minY))
            ctx.restoreGState()
        }
        ridge([(-0.05, 0.30), (0.22, 0.62), (0.42, 0.36), (0.66, 0.56), (0.86, 0.34), (1.05, 0.46)],
              color(0x8C7BFF), color(0x6A5BE8))
        ridge([(-0.05, 0.12), (0.18, 0.40), (0.38, 0.16), (0.60, 0.44), (0.80, 0.18), (1.05, 0.30)],
              color(0x4B3BC7), color(0x2E2390))
        ctx.restoreGState()
    }
    ctx.restoreGState()
}

func drawChevron(_ ctx: CGContext, at p: CGPoint, pointingRight: Bool) {
    let w: CGFloat = 34, h: CGFloat = 62
    let dir: CGFloat = pointingRight ? 1 : -1
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: color(0x1B0B4A, 0.35))
    ctx.setStrokeColor(color(0xFFFFFF, 0.95))
    ctx.setLineWidth(22)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: p.x - dir * w / 2, y: p.y + h / 2))
    ctx.addLine(to: CGPoint(x: p.x + dir * w / 2, y: p.y))
    ctx.addLine(to: CGPoint(x: p.x - dir * w / 2, y: p.y - h / 2))
    ctx.strokePath()
    ctx.restoreGState()
}

func drawIcon(in ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.30))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x5B3CF0))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Background: indigo → violet → coral.
    linearGradient(ctx, [color(0x4F46E5), color(0x8B3FE8), color(0xF25C9A), color(0xFF9466)],
                   from: CGPoint(x: body.minX, y: body.maxY), to: CGPoint(x: body.maxX, y: body.minY),
                   locations: [0, 0.38, 0.75, 1])
    // Soft light from the top-left.
    let light = CGGradient(colorsSpace: sRGB, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: CGPoint(x: 260, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 260, y: 860), endRadius: 620, options: [])

    // Photos.
    drawPhoto(ctx, center: CGPoint(x: 500, y: 540), size: CGSize(width: 500, height: 400), angle: 11, faded: true)
    drawPhoto(ctx, center: CGPoint(x: 512, y: 500), size: CGSize(width: 540, height: 430), angle: -4, faded: false)

    // Browse arrows.
    drawChevron(ctx, at: CGPoint(x: 176, y: 500), pointingRight: false)
    drawChevron(ctx, at: CGPoint(x: 848, y: 500), pointingRight: true)

    ctx.restoreGState()

    // Hairline highlight on the rim.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()
}

func render(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    let scale = CGFloat(size) / 1024
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(in: ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png").path)
    writePNG(render(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png").path)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsPath]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)

if let previewPath { writePNG(render(size: 1024), to: previewPath) }
print("Wrote \(icnsPath)\(previewPath.map { " and \($0)" } ?? "")")
