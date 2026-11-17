import Foundation

/// File helpers: Finder-style copy names, undo backups, safe replacement.
public enum FileOps {
    /// Where originals are stashed before being overwritten, so edits can be undone.
    public static var backupDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "zzPic", isDirectory: true)
            .appendingPathComponent("UndoBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes the backups of previous sessions (undo history does not survive a relaunch).
    public static func clearBackups() {
        let dir = backupDirectory
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for item in items { try? FileManager.default.removeItem(at: item) }
    }

    public static func makeBackup(of url: URL) throws -> URL {
        var dest = backupDirectory.appendingPathComponent(UUID().uuidString)
        if !url.pathExtension.isEmpty { dest.appendPathExtension(url.pathExtension) }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    /// A hidden scratch file next to `url` (same volume, so it can be swapped in atomically).
    public static func temporaryURL(near url: URL, pathExtension: String) -> URL {
        let name = ".zzpic-\(UUID().uuidString.prefix(8))"
        var temp = url.deletingLastPathComponent().appendingPathComponent(name)
        if !pathExtension.isEmpty { temp.appendPathExtension(pathExtension) }
        return temp
    }

    /// "photo copy.jpg", "photo copy 2.jpg", … (the word "copy" is localized like in Finder).
    public static func uniqueCopyURL(for url: URL, pathExtension: String? = nil) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = pathExtension ?? url.pathExtension
        let word = L("copy")
        var n = 1
        while true {
            let name = n == 1 ? "\(base) \(word)" : "\(base) \(word) \(n)"
            var candidate = dir.appendingPathComponent(name)
            if !ext.isEmpty { candidate.appendPathExtension(ext) }
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// Replaces `url` with `newFile` (which is moved), keeping the original's attributes when possible.
    public static func replace(_ url: URL, with newFile: URL) throws {
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: newFile)
        } catch {
            // Some file systems (exFAT, SMB…) don't support atomic replacement.
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: newFile, to: url)
        }
    }
}
