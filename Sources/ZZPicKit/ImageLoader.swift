import AppKit
import ImageIO

/// A decoded image ready to be displayed (already rotated according to its EXIF orientation).
public struct LoadedImage: @unchecked Sendable {
    public let url: URL
    /// Decoded, upright bitmap (nil for animated images).
    public let image: CGImage?
    /// Set for animated GIF / PNG / WebP files, displayed by `NSImageView`.
    public let animatedImage: NSImage?
    /// Upright size in pixels of the original file.
    public let pixelSize: CGSize
    public let fileSize: Int64
    public let typeIdentifier: String?
    public let modificationDate: Date?

    public var isAnimated: Bool { animatedImage != nil }

    var cost: Int {
        if let image { return image.bytesPerRow * image.height }
        return Int(pixelSize.width * pixelSize.height * 4)
    }
}

public enum ImageLoadError: LocalizedError {
    case unreadable(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            return LF("“%@” can’t be opened because it isn’t a supported image.", url.lastPathComponent)
        }
    }
}

/// Decodes images off the main thread and keeps a small LRU cache so that
/// moving back and forth between neighbours is instant.
public final class ImageLoader: @unchecked Sendable {
    public static let shared = ImageLoader()

    /// Bitmaps larger than this are downsampled for display (the file is never touched).
    public static let maxDisplayDimension = 8192

    private static let animatedTypes: Set<String> = ["com.compuserve.gif", "public.png", "org.webmproject.webp"]

    private let lock = NSLock()
    private var cache: [String: LoadedImage] = [:]
    private var order: [String] = []
    private var tasks: [String: Task<LoadedImage, Error>] = [:]
    private let countLimit = 7
    private let costLimit = 800 * 1024 * 1024

    public init() {}

    public func load(_ url: URL) async throws -> LoadedImage {
        let key = url.fileKey
        let task: Task<LoadedImage, Error> = lock.withLock {
            if let hit = cache[key], Self.isFresh(hit) {
                touch(key)
                return Task { hit }
            }
            if let running = tasks[key] { return running }
            let task = Task.detached(priority: .userInitiated) { [weak self] () throws -> LoadedImage in
                do {
                    let image = try Self.decode(url)
                    self?.store(image, key: key)
                    return image
                } catch {
                    self?.finish(key)
                    throw error
                }
            }
            tasks[key] = task
            return task
        }
        return try await task.value
    }

    /// Returns the cached image immediately, if any.
    public func cachedImage(for url: URL) -> LoadedImage? {
        lock.withLock {
            guard let hit = cache[url.fileKey], Self.isFresh(hit) else { return nil }
            return hit
        }
    }

    /// Decodes the given files in the background so they are ready when needed.
    public func prefetch(_ urls: [URL]) {
        for url in urls {
            Task.detached(priority: .utility) { [weak self] in
                _ = try? await self?.load(url)
            }
        }
    }

    public func invalidate(_ url: URL) {
        let key = url.fileKey
        lock.withLock {
            cache[key] = nil
            order.removeAll { $0 == key }
        }
    }

    // MARK: - Cache bookkeeping (called with or without the lock as noted)

    /// Requires the lock.
    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func finish(_ key: String) {
        lock.withLock { tasks[key] = nil }
    }

    private func store(_ image: LoadedImage, key: String) {
        lock.withLock {
            tasks[key] = nil
            cache[key] = image
            touch(key)
            var total = cache.values.reduce(0) { $0 + $1.cost }
            while order.count > 1, order.count > countLimit || total > costLimit {
                let evicted = order.removeFirst()
                total -= cache[evicted]?.cost ?? 0
                cache[evicted] = nil
            }
        }
    }

    private static func isFresh(_ image: LoadedImage) -> Bool {
        let date = (try? image.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return date == image.modificationDate
    }

    // MARK: - Decoding

    static func decode(_ url: URL) throws -> LoadedImage {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageLoadError.unreadable(url)
        }
        let type = CGImageSourceGetType(source) as String?
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        var height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        if ExifOrientation.swapsDimensions(orientation) { swap(&width, &height) }

        let fileSize = Int64(values?.fileSize ?? 0)
        let modified = values?.contentModificationDate

        if CGImageSourceGetCount(source) > 1, let type, animatedTypes.contains(type),
           let animated = NSImage(contentsOf: url) {
            let size = width > 0 ? CGSize(width: width, height: height) : animated.size
            return LoadedImage(url: url, image: nil, animatedImage: animated, pixelSize: size,
                               fileSize: fileSize, typeIdentifier: type, modificationDate: modified)
        }

        let longest = max(width, height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longest > 0 ? min(longest, maxDisplayDimension) : maxDisplayDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageLoadError.unreadable(url)
        }
        if width == 0 || height == 0 {
            width = image.width
            height = image.height
        }
        return LoadedImage(url: url, image: image, animatedImage: nil,
                           pixelSize: CGSize(width: width, height: height),
                           fileSize: fileSize, typeIdentifier: type, modificationDate: modified)
    }
}

/// Small thumbnails for the filmstrip.
public final class ThumbnailProvider: @unchecked Sendable {
    public static let shared = ThumbnailProvider()

    private let cache = NSCache<NSString, CGImage>()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .utility
        return queue
    }()

    public init() {
        cache.countLimit = 800
    }

    public func cachedThumbnail(for url: URL) -> CGImage? {
        cache.object(forKey: url.fileKey as NSString)
    }

    public func thumbnail(for url: URL, maxPixelSize: Int = 200) async -> CGImage? {
        let key = url.fileKey as NSString
        if let hit = cache.object(forKey: key) { return hit }
        return await withCheckedContinuation { continuation in
            queue.addOperation { [cache] in
                let image = Self.makeThumbnail(url, maxPixelSize: maxPixelSize)
                if let image { cache.setObject(image, forKey: key) }
                continuation.resume(returning: image)
            }
        }
    }

    public func invalidate(_ url: URL) {
        cache.removeObject(forKey: url.fileKey as NSString)
    }

    static func makeThumbnail(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
