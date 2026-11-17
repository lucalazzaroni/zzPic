import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum EditOperation: Sendable, Equatable {
    case rotate(clockwise: Bool)
    /// Normalized rectangle (0…1) in upright image coordinates, origin at the top-left.
    case crop(CGRect)
    case resize(width: Int, height: Int)
}

public enum ImageEditError: LocalizedError {
    case unreadable
    case cannotWrite(String)
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .unreadable: return L("The image could not be read.")
        case .cannotWrite(let name): return LF("“%@” could not be saved.", name)
        case .renderFailed: return L("The edited image could not be created.")
        }
    }
}

/// Simple, format-preserving edits: rotate, crop, resize.
public enum ImageEditor {
    /// Formats whose rotation can be done by just rewriting the EXIF orientation (no recompression).
    static let losslessRotationTypes: Set<String> = ["public.jpeg", "public.heic", "public.heif", "public.tiff"]

    public static let writableTypes: Set<String> =
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    public static func typeIdentifier(of url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceGetType(source) as String?
    }

    /// `true` if zzPic can write files of this type back in the same format.
    public static func canWrite(type: String?) -> Bool {
        guard let type else { return false }
        return writableTypes.contains(type)
    }

    /// Applies `operation` to the image at `source` and writes the result to `output`
    /// (which must not exist yet) using `outputType`.
    public static func render(_ operation: EditOperation, source url: URL, output: URL, outputType: String) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(source) as String? else {
            throw ImageEditError.unreadable
        }
        let props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1

        // Lossless path: just update the orientation flag.
        if case .rotate(let clockwise) = operation,
           outputType == sourceType,
           losslessRotationTypes.contains(sourceType),
           let destination = CGImageDestinationCreateWithURL(output as CFURL, sourceType as CFString, 1, nil) {
            let newOrientation = ExifOrientation.rotated(orientation, clockwise: clockwise)
            let options: [CFString: Any] = [kCGImageDestinationOrientation: newOrientation]
            if CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) {
                return
            }
            try? FileManager.default.removeItem(at: output)
        }

        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImageEditError.unreadable }
        var edited = try orient(raw, orientation: orientation)

        switch operation {
        case .rotate(let clockwise):
            edited = try orient(edited, orientation: clockwise ? 6 : 8)
        case .crop(let normalized):
            edited = try crop(edited, normalized: normalized)
        case .resize(let width, let height):
            edited = try resample(edited, width: width, height: height)
        }

        try write(edited, to: output, type: outputType, sourceType: sourceType, properties: props)
    }

    /// The full-resolution, upright image (for printing).
    public static func uprightImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageEditError.unreadable
        }
        let props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        return try orient(raw, orientation: orientation)
    }

    // MARK: - Pixel operations

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static func outputColorSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb { return space }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// Applies an EXIF orientation to the pixels.
    static func orient(_ image: CGImage, orientation: UInt32) throws -> CGImage {
        guard orientation != 1 else { return image }
        var ci = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation))
        ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))
        return try render(ci, like: image)
    }

    static func crop(_ image: CGImage, normalized rect: CGRect) throws -> CGImage {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        var pixels = CGRect(x: (rect.minX * width).rounded(),
                            y: (rect.minY * height).rounded(),
                            width: (rect.width * width).rounded(),
                            height: (rect.height * height).rounded())
        pixels = pixels.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard pixels.width >= 1, pixels.height >= 1, let cropped = image.cropping(to: pixels) else {
            throw ImageEditError.renderFailed
        }
        return cropped
    }

    static func resample(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0 else { throw ImageEditError.renderFailed }
        let deep = image.bitsPerComponent > 8
        let space = outputColorSpace(for: image)
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: deep ? 16 : 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context else { throw ImageEditError.renderFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw ImageEditError.renderFailed }
        return result
    }

    private static func render(_ ci: CIImage, like original: CGImage) throws -> CGImage {
        let format: CIFormat = original.bitsPerComponent > 8 ? .RGBA16 : .RGBA8
        guard let image = ciContext.createCGImage(ci, from: ci.extent, format: format,
                                                  colorSpace: outputColorSpace(for: original)) else {
            throw ImageEditError.renderFailed
        }
        return image
    }

    // MARK: - Writing

    private static let portableMetadataKeys: [CFString] = [
        kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary,
        kCGImagePropertyIPTCDictionary, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight,
    ]

    static func write(_ image: CGImage, to url: URL, type: String, sourceType: String,
                      properties: [CFString: Any]) throws {
        var meta: [CFString: Any]
        if type == sourceType {
            meta = properties
        } else {
            meta = [:]
            for key in portableMetadataKeys { meta[key] = properties[key] }
        }
        meta.removeValue(forKey: kCGImagePropertyPixelWidth)
        meta.removeValue(forKey: kCGImagePropertyPixelHeight)
        meta[kCGImagePropertyOrientation] = 1
        if var tiff = meta[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            meta[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = meta[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = image.width
            exif[kCGImagePropertyExifPixelYDimension] = image.height
            meta[kCGImagePropertyExifDictionary] = exif
        }
        meta[kCGImageDestinationLossyCompressionQuality] = 0.92

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw ImageEditError.cannotWrite(url.lastPathComponent)
        }
        CGImageDestinationAddImage(destination, image, meta as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw ImageEditError.cannotWrite(url.lastPathComponent)
        }
    }
}
