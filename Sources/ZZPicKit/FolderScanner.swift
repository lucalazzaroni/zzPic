import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageSortOrder: String, CaseIterable, Sendable {
    case name, dateModified, size
}

/// Lists the images contained in a folder, in Finder-like order.
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

    public static func isImageFile(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return isReadableImageType(type)
    }

    /// Returns every readable, non-hidden image in `folder`.
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
                  isReadableImageType(type) else { continue }
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
