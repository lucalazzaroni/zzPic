import AVFoundation
import Foundation

/// Basic facts about a video file, for the title bar and the info panel.
public struct VideoInfo: Sendable {
    public let url: URL
    /// Display size (rotation already applied).
    public let pixelSize: CGSize
    public let duration: Double
    public let frameRate: Float
    public let codec: String?
    public let hasAudio: Bool
    public let fileSize: Int64

    /// "0:42", "12:05", "1:02:03".
    public var durationText: String {
        guard duration.isFinite, duration >= 0 else { return "–" }
        let total = Int(duration.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    public static func load(_ url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ImageLoadError.unreadable(url)
        }
        let duration = try await asset.load(.duration)
        let (naturalSize, transform, frameRate, formats) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
        let size = naturalSize.applying(transform)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return VideoInfo(url: url,
                         pixelSize: CGSize(width: abs(size.width), height: abs(size.height)),
                         duration: CMTimeGetSeconds(duration),
                         frameRate: frameRate,
                         codec: formats.first.map { codecName(CMFormatDescriptionGetMediaSubType($0)) },
                         hasAudio: !audio.isEmpty,
                         fileSize: Int64(fileSize))
    }

    static func codecName(_ code: FourCharCode) -> String {
        let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((code >> $0) & 0xFF))) }
        let fourCC = String(chars).trimmingCharacters(in: .whitespaces)
        switch fourCC {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "av01": return "AV1"
        case "vp09": return "VP9"
        case "mp4v": return "MPEG-4"
        case "jpeg": return "Motion JPEG"
        case let c where c.hasPrefix("ap"): return "ProRes"
        default: return fourCC
        }
    }
}
