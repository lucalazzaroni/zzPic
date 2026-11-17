import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageSortOrder: String, CaseIterable, Sendable {
    case name, dateModified, size
}

/// Lists the images and videos contained in a folder, in Finder-like order.
public enum FolderScanner {
    private static let readableIdentifiers: Set<String> =
        Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
    private static let readableTypes: [UTType] = readableIdentifiers.compactMap { UTType($0) }

    /// `true` when ImageIO can decode files of this type.
    public static func isReadableImageType(_ type: UTType) -> Bool {
        guard type.conforms(to: .image) else { return false }
        if readableIdentifiers.contains(type.identifier) { return true }
        return readableTypes.contains { type.conforms(to: $0) }
    }

    private static let playableIdentifiers: Set<String> = Set(AVURLAsset.audiovisualTypes().map(\.rawValue))
    private static let playableTypes: [UTType] = playableIdentifiers.compactMap { UTType($0) }.filter { $0.conforms(to: .movie) }

    /// `true` for video formats AVFoundation can play (audio-only files are excluded).
    public static func isPlayableVideoType(_ type: UTType) -> Bool {
        guard type.conforms(to: .movie), !type.conforms(to: .audio) || type.conforms(to: .video) else { return false }
        if playableIdentifiers.contains(type.identifier) { return true }
        return playableTypes.contains { type.conforms(to: $0) }
    }

    private static func contentType(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
    }

    public static func isImageFile(_ url: URL) -> Bool {
        contentType(of: url).map(isReadableImageType) ?? false
    }

    public static func isVideoFile(_ url: URL) -> Bool {
        contentType(of: url).map(isPlayableVideoType) ?? false
    }

    /// An image or a video zzPic can show.
    public static func isMediaFile(_ url: URL) -> Bool {
        guard let type = contentType(of: url) else { return false }
        return isReadableImageType(type) || isPlayableVideoType(type)
    }

    /// Returns every readable, non-hidden image and video in `folder`.
    public static func scan(folder: URL, sortedBy order: ImageSortOrder) -> [URL] {
        let keys: [URLResourceKey] = [.contentTypeKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        struct Entry { let url: URL; let name: String; let date: Date; let size: Int }
        var entries: [Entry] = []
        entries.reserveCapacity(items.count)
        for url in items {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let type = values.contentType,
                  isReadableImageType(type) || isPlayableVideoType(type) else { continue }
            entries.append(Entry(url: url,
                                 name: url.lastPathComponent,
                                 date: values.contentModificationDate ?? .distantPast,
                                 size: values.fileSize ?? 0))
        }

        func byName(_ a: Entry, _ b: Entry) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        switch order {
        case .name:
            entries.sort(by: byName)
        case .dateModified:
            entries.sort { $0.date != $1.date ? $0.date < $1.date : byName($0, $1) }
        case .size:
            entries.sort { $0.size != $1.size ? $0.size < $1.size : byName($0, $1) }
        }
        return entries.map(\.url)
    }
}

public extension URL {
    /// Stable key to compare file URLs (standardized path, canonical Unicode form).
    var fileKey: String {
        standardizedFileURL.path.precomposedStringWithCanonicalMapping
    }

    func isSameFile(as other: URL) -> Bool {
        fileKey == other.fileKey
    }
}

public extension Array where Element == URL {
    func firstIndex(ofFile url: URL) -> Int? {
        let key = url.fileKey
        return firstIndex { $0.fileKey == key }
    }
}
