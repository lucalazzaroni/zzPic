import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ZZPicKit

// MARK: - Helpers

/// A width×height image whose left half is red and right half is blue.
private func makeSplitImage(width: Int = 40, height: Int = 20) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    return ctx.makeImage()!
}

private func write(_ image: CGImage, to url: URL, type: UTType, orientation: UInt32 = 1) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    let props: [CFString: Any] = [kCGImagePropertyOrientation: orientation,
                                  kCGImageDestinationLossyCompressionQuality: 1.0]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    precondition(CGImageDestinationFinalize(dest))
}

/// Upright RGBA pixel (0…255) at x, y (origin top-left).
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let i = (y * w + x) * 4
    return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
}

private func isRed(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 180 && p.b < 80 }
private func isBlue(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.b > 180 && p.r < 80 }

private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zzpic-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func orientation(of url: URL) -> UInt32 {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
    return (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
}

// MARK: - Orientation

@Test func orientationRotatesClockwise() {
    #expect(ExifOrientation.rotated(1, clockwise: true) == 6)
    #expect(ExifOrientation.rotated(6, clockwise: true) == 3)
    #expect(ExifOrientation.rotated(3, clockwise: true) == 8)
    #expect(ExifOrientation.rotated(8, clockwise: true) == 1)
    #expect(ExifOrientation.rotated(1, clockwise: false) == 8)
}

@Test func orientationRoundTrips() {
    for o in UInt32(1)...8 {
        let cw = ExifOrientation.rotated(o, clockwise: true)
        #expect(ExifOrientation.rotated(cw, clockwise: false) == o)
        var x = o
        for _ in 0..<4 { x = ExifOrientation.rotated(x, clockwise: true) }
        #expect(x == o)
    }
}

// MARK: - Editing

@Test func losslessJPEGRotationOnlyChangesOrientation() throws {
    let dir = tempDir()
    let src = dir.appendingPathComponent("a.jpg")
    write(makeSplitImage(), to: src, type: .jpeg)
    let out = dir.appendingPathComponent("b.jpg")
    try ImageEditor.render(.rotate(clockwise: true), source: src, output: out, outputType: "public.jpeg")

    #expect(orientation(of: out) == 6)
    let loaded = try ImageLoader.decode(out)
    #expect(loaded.pixelSize == CGSize(width: 20, height: 40))
    // Left half (red) must now be on top.
    #expect(isRed(pixel(loaded.image!, 10, 5)))
    #expect(isBlue(pixel(loaded.image!, 10, 35)))
}

@Test func pngRotationReencodesPixels() throws {
    let dir = tempDir()
    let src = dir.appendingPathComponent("a.png")
    write(makeSplitImage(), to: src, type: .png)
    let out = dir.appendingPathComponent("b.png")
    try ImageEditor.render(.rotate(clockwise: false), source: src, output: out, outputType: "public.png")

    let loaded = try ImageLoader.decode(out)
    #expect(loaded.pixelSize == CGSize(width: 20, height: 40))
    // Counter-clockwise: left half (red) ends up at the bottom.
    #expect(isBlue(pixel(loaded.image!, 10, 5)))
    #expect(isRed(pixel(loaded.image!, 10, 35)))
}

@Test func cropUsesTopLeftNormalizedRect() throws {
    let dir = tempDir()
    let src = dir.appendingPathComponent("a.png")
    write(makeSplitImage(), to: src, type: .png)
    let out = dir.appendingPathComponent("b.png")
    try ImageEditor.render(.crop(CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)), source: src, output: out,
                           outputType: "public.png")
    let loaded = try ImageLoader.decode(out)
    #expect(loaded.pixelSize == CGSize(width: 20, height: 10))
    #expect(isBlue(pixel(loaded.image!, 2, 2)))
    #expect(isBlue(pixel(loaded.image!, 18, 8)))
}

@Test func cropRespectsExifOrientation() throws {
    let dir = tempDir()
    let src = dir.appendingPathComponent("a.jpg")
    // Stored 40×20 (red left), displayed rotated 90° CW: 20×40 with red on top.
    write(makeSplitImage(), to: src, type: .jpeg, orientation: 6)
    let out = dir.appendingPathComponent("b.jpg")
    // Keep the top half of the *displayed* image.
    try ImageEditor.render(.crop(CGRect(x: 0, y: 0, width: 1, height: 0.5)), source: src, output: out,
                           outputType: "public.jpeg")
    #expect(orientation(of: out) == 1)
    let loaded = try ImageLoader.decode(out)
    #expect(loaded.pixelSize == CGSize(width: 20, height: 20))
    #expect(isRed(pixel(loaded.image!, 10, 10)))
}

@Test func resizeProducesRequestedSize() throws {
    let dir = tempDir()
    let src = dir.appendingPathComponent("a.png")
    write(makeSplitImage(), to: src, type: .png)
    let out = dir.appendingPathComponent("b.png")
    try ImageEditor.render(.resize(width: 10, height: 5), source: src, output: out, outputType: "public.png")
    let loaded = try ImageLoader.decode(out)
    #expect(loaded.pixelSize == CGSize(width: 10, height: 5))
    #expect(isRed(pixel(loaded.image!, 1, 2)))
    #expect(isBlue(pixel(loaded.image!, 8, 2)))
}

// MARK: - Folder scanning & files

@Test func scannerSortsNaturallyAndSkipsNonImages() {
    let dir = tempDir()
    for name in ["img10.png", "img2.png", "img1.png", ".hidden.png"] {
        write(makeSplitImage(width: 4, height: 4), to: dir.appendingPathComponent(name), type: .png)
    }
    try! "hello".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    let names = FolderScanner.scan(folder: dir, sortedBy: .name).map(\.lastPathComponent)
    #expect(names == ["img1.png", "img2.png", "img10.png"])
}

@Test func uniqueCopyNamesDoNotCollide() throws {
    let dir = tempDir()
    let original = dir.appendingPathComponent("photo.jpg")
    try Data([1]).write(to: original)
    let first = FileOps.uniqueCopyURL(for: original)
    #expect(first.lastPathComponent == "photo copy.jpg")
    try Data([1]).write(to: first)
    #expect(FileOps.uniqueCopyURL(for: original).lastPathComponent == "photo copy 2.jpg")
    #expect(FileOps.uniqueCopyURL(for: original, pathExtension: "png").lastPathComponent == "photo copy.png")
}

@Test func replaceSwapsContents() throws {
    let dir = tempDir()
    let a = dir.appendingPathComponent("a.bin"), b = dir.appendingPathComponent("b.bin")
    try Data([1]).write(to: a)
    try Data([2]).write(to: b)
    try FileOps.replace(a, with: b)
    #expect(try Data(contentsOf: a) == Data([2]))
    #expect(!FileManager.default.fileExists(atPath: b.path))
}
