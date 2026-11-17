import Foundation
import Observation
import ZZPicKit

enum CropAspect: String, CaseIterable, Identifiable {
    case free, original, square, fourThree, threeTwo, sixteenNine

    var id: Self { self }

    var title: String {
        switch self {
        case .free: return L("Freeform")
        case .original: return L("Original")
        case .square: return L("Square")
        case .fourThree: return "4:3"
        case .threeTwo: return "3:2"
        case .sixteenNine: return "16:9"
        }
    }

    /// Width / height, or nil for freeform.
    func ratio(for pixelSize: CGSize, portrait: Bool) -> CGFloat? {
        let base: CGFloat
        switch self {
        case .free: return nil
        case .original: return pixelSize.height > 0 ? pixelSize.width / pixelSize.height : nil
        case .square: return 1
        case .fourThree: base = 4 / 3
        case .threeTwo: base = 3 / 2
        case .sixteenNine: base = 16 / 9
        }
        return portrait ? 1 / base : base
    }

    var canFlip: Bool {
        switch self {
        case .free, .original, .square: return false
        default: return true
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let symbol: String
    let canUndo: Bool
}

struct ResizeRequest: Identifiable {
    let id = UUID()
    let pixelSize: CGSize
    let canOverwrite: Bool
}

/// Everything the SwiftUI part of a viewer window displays.
@Observable @MainActor
final class ViewerModel {
    var files: [URL] = []
    var index = 0
    var loaded: LoadedImage?
    var video: VideoInfo?
    var loadError: String?
    var showSpinner = false

    var isCropping = false
    var cropAspect: CropAspect = .free
    var cropPortrait = false
    var cropPixelSize: CGSize = .zero

    var showFilmstrip: Bool = UserDefaults.standard.object(forKey: "showFilmstrip") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showFilmstrip, forKey: "showFilmstrip") }
    }
    var showInspector: Bool = UserDefaults.standard.bool(forKey: "showInspector") {
        didSet { UserDefaults.standard.set(showInspector, forKey: "showInspector") }
    }
    var metadata: [MetadataSection] = []

    var toast: Toast?
    var zoomHUD: String?
    var resizeRequest: ResizeRequest?
    var isBusy = false
    /// Bumped when a file changes on disk, to refresh its thumbnail.
    var revisions: [String: Int] = [:]

    var current: URL? { files.indices.contains(index) ? files[index] : nil }

    /// The loaded image, only if it belongs to the current file.
    var currentImage: LoadedImage? {
        guard let loaded, let current, loaded.url.isSameFile(as: current) else { return nil }
        return loaded
    }

    /// Info about the current file if it is a video (nil while it loads).
    var currentVideo: VideoInfo? {
        guard let video, let current, video.url.isSameFile(as: current) else { return nil }
        return video
    }

    var currentIsVideo: Bool { current.map(FolderScanner.isVideoFile) ?? false }

    var canEdit: Bool { currentImage.map { !$0.isAnimated } ?? false }

    var canOverwrite: Bool {
        guard let image = currentImage, !image.isAnimated else { return false }
        return ImageEditor.canWrite(type: image.typeIdentifier)
    }

    func revision(of url: URL) -> Int { revisions[url.fileKey] ?? 0 }
}
