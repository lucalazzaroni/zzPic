import AppKit
import AVKit
import ZZPicKit

enum NavigationStep {
    case previous, next, first, last
}

@MainActor
protocol ImageCanvasDelegate: AnyObject {
    var canvasFileURL: URL? { get }
    func canvasNavigate(_ step: NavigationStep)
    func canvasDeleteRequested()
    func canvasEscapePressed()
    func canvasZoomChanged(percent: Int, isFit: Bool, userInitiated: Bool)
    func canvasCropChanged(pixelSize: CGSize)
    func canvasReceivedDrop(_ urls: [URL])
}

extension NSColor {
    /// Neutral backdrop behind photos.
    static let zzCanvas = NSColor(name: "zzCanvas") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.085, green: 0.085, blue: 0.095, alpha: 1)
            : NSColor(srgbRed: 0.925, green: 0.925, blue: 0.935, alpha: 1)
    }
}

/// The zoomable image area: an `NSScrollView` with magnification plus the crop overlay.
/// One document point equals one image pixel, so 100 % = "actual size".
final class ImageCanvasView: NSView {
    enum ZoomMode { case fit, custom }

    weak var delegate: ImageCanvasDelegate?

    let scrollView = ZoomScrollView()
    let documentView = ImageDocumentView()
    private let clipView = CenteringClipView()
    private let cropOverlay = CropOverlayView()

    private(set) var pixelSize: CGSize = .zero
    private(set) var zoomMode: ZoomMode = .fit
    private(set) var isCropping = false
    private(set) var hasImage = false
    private(set) var isShowingVideo = false
    private var playerView: AVPlayerView?
    private var videoSize: CGSize?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        clipView.drawsBackground = true
        clipView.backgroundColor = .zzCanvas
        clipView.postsBoundsChangedNotifications = true
        scrollView.contentView = clipView
        scrollView.documentView = documentView
        scrollView.canvas = self
        documentView.canvas = self
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .zzCanvas
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.01
        scrollView.maxMagnification = 32
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        cropOverlay.frame = bounds
        cropOverlay.autoresizingMask = [.width, .height]
        cropOverlay.isHidden = true
        cropOverlay.onChange = { [weak self] _ in self?.cropDidChange() }
        addSubview(cropOverlay)

        registerForDraggedTypes([.fileURL])

        NotificationCenter.default.addObserver(self, selector: #selector(liveMagnifyEnded),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged),
                                               name: NSView.boundsDidChangeNotification, object: clipView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if zoomMode == .fit { applyFit() }
        updateCropGeometry()
        layoutPlayer()
    }

    // MARK: - Content

    func display(_ image: LoadedImage?) {
        stopVideo()
        guard let image else {
            hasImage = false
            pixelSize = .zero
            documentView.setImage(nil, animated: nil)
            documentView.frame = .zero
            return
        }
        hasImage = true
        pixelSize = image.pixelSize
        documentView.setImage(image.image, animated: image.animatedImage)
        documentView.frame = NSRect(origin: .zero, size: NSSize(width: max(1, pixelSize.width),
                                                                height: max(1, pixelSize.height)))
        zoomMode = .fit
        applyFit()
    }

    // MARK: - Video

    func displayVideo(_ url: URL) {
        display(nil)
        let view = playerView ?? makePlayerView()
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        view.player = player
        videoSize = nil
        view.alphaValue = 0          // revealed by setVideoSize once the dimensions are known
        view.isHidden = false
        isShowingVideo = true
        player.play()
    }

    /// Sizes the player to the video's aspect ratio so the backdrop matches photos.
    /// Pass nil if the size is unknown: the player then fills the canvas.
    func setVideoSize(_ size: CGSize?) {
        guard isShowingVideo else { return }
        videoSize = size
        layoutPlayer()
        playerView?.alphaValue = 1
    }

    private func layoutPlayer() {
        guard let playerView, isShowingVideo else { return }
        guard let size = videoSize, size.width > 0, size.height > 0 else {
            playerView.frame = bounds
            return
        }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let w = (size.width * scale).rounded(), h = (size.height * scale).rounded()
        playerView.frame = NSRect(x: ((bounds.width - w) / 2).rounded(), y: ((bounds.height - h) / 2).rounded(),
                                  width: w, height: h)
    }

    func stopVideo() {
        guard let playerView else { return }
        playerView.player?.pause()
        playerView.player = nil
        playerView.isHidden = true
        isShowingVideo = false
    }

    func togglePlayback() {
        guard let player = playerView?.player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            if let item = player.currentItem, item.currentTime() >= item.duration { player.seek(to: .zero) }
            player.play()
        }
    }

    private func makePlayerView() -> AVPlayerView {
        let view = AVPlayerView(frame: bounds)
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = false
        view.showsSharingServiceButton = false
        view.allowsPictureInPicturePlayback = true
        view.isHidden = true
        addSubview(view, positioned: .above, relativeTo: scrollView)
        playerView = view
        return view
    }

    // MARK: - Zoom

    var visibleCenter: NSPoint {
        NSPoint(x: clipView.bounds.midX, y: clipView.bounds.midY)
    }

    /// `true` when the whole image is visible (nothing to scroll).
    var contentFits: Bool {
        let size = documentView.frame.size
        let mag = scrollView.magnification
        return size.width * mag <= scrollView.contentSize.width + 1
            && size.height * mag <= scrollView.contentSize.height + 1
    }

    func fitMagnification() -> CGFloat {
        let doc = documentView.frame.size
        guard doc.width > 0, doc.height > 0 else { return 1 }
        let inset: CGFloat = isCropping ? 36 : 0
        let available = NSSize(width: max(20, scrollView.contentSize.width - inset * 2),
                               height: max(20, scrollView.contentSize.height - inset * 2))
        var mag = min(available.width / doc.width, available.height / doc.height)
        if !isCropping { mag = min(mag, 1) }   // never blow small images up
        return mag
    }

    func applyFit() {
        guard hasImage else { return }
        let mag = fitMagnification()
        scrollView.minMagnification = min(mag, 1)
        let doc = documentView.frame
        scrollView.setMagnification(mag, centeredAt: NSPoint(x: doc.midX, y: doc.midY))
        zoomMode = .fit
        zoomDidChange(userInitiated: false)
    }

    func zoom(by factor: CGFloat, around point: NSPoint? = nil) {
        guard hasImage, !isCropping else { return }
        let current = scrollView.magnification
        var target = current * factor
        // Stop at 100 % on the way through, it's the most useful zoom level.
        if (current < 1 && target > 1) || (current > 1 && target < 1) { target = 1 }
        target = min(max(target, scrollView.minMagnification), scrollView.maxMagnification)
        scrollView.setMagnification(target, centeredAt: point ?? visibleCenter)
        zoomMode = abs(target - fitMagnification()) < 0.0005 ? .fit : .custom
        zoomDidChange(userInitiated: true)
    }

    func zoomIn() { zoom(by: 1.25) }
    func zoomOut() { zoom(by: 1 / 1.25) }

    func actualSize(around point: NSPoint? = nil) {
        guard hasImage, !isCropping else { return }
        scrollView.setMagnification(1, centeredAt: point ?? visibleCenter)
        zoomMode = abs(1 - fitMagnification()) < 0.0005 ? .fit : .custom
        zoomDidChange(userInitiated: true)
    }

    func zoomToFit() {
        guard hasImage, !isCropping else { return }
        applyFit()
        zoomDidChange(userInitiated: true)
    }

    /// Double-click / smart zoom: fit ⇄ 100 % (or 2× for images smaller than the window).
    func toggleZoom(at point: NSPoint?) {
        guard hasImage, !isCropping else { return }
        if zoomMode == .fit {
            let fit = fitMagnification()
            if fit < 0.999 { actualSize(around: point) } else { zoom(by: 2, around: point) }
        } else {
            zoomToFit()
        }
    }

    func magnificationChangedByGesture() {
        let fit = fitMagnification()
        if scrollView.magnification <= fit + 0.0005 {
            zoomMode = .fit
        } else {
            zoomMode = .custom
        }
        zoomDidChange(userInitiated: true)
    }

    @objc private func liveMagnifyEnded() {
        magnificationChangedByGesture()
    }

    private func zoomDidChange(userInitiated: Bool) {
        window?.invalidateCursorRects(for: documentView)
        let percent = Int((scrollView.magnification * 100).rounded())
        delegate?.canvasZoomChanged(percent: percent, isFit: zoomMode == .fit, userInitiated: userInitiated)
    }

    @objc private func clipBoundsChanged() {
        updateCropGeometry()
    }

    // MARK: - Crop

    var cropNormalizedRect: CGRect { cropOverlay.normalizedRect }

    func beginCrop(aspect: CGFloat?) {
        guard hasImage else { return }
        isCropping = true
        scrollView.allowsMagnification = false
        applyFit()
        cropOverlay.isHidden = false
        updateCropGeometry()
        cropOverlay.reset(aspect: aspect)
        window?.makeFirstResponder(scrollView)
    }

    func endCrop() {
        guard isCropping else { return }
        isCropping = false
        cropOverlay.isHidden = true
        scrollView.allowsMagnification = true
        applyFit()
    }

    func setCropAspect(_ aspect: CGFloat?) {
        cropOverlay.setAspect(aspect)
    }

    private func updateCropGeometry() {
        guard isCropping, hasImage else { return }
        cropOverlay.imageRect = documentView.convert(documentView.bounds, to: cropOverlay)
    }

    private func cropDidChange() {
        let n = cropOverlay.normalizedRect
        let size = CGSize(width: (n.width * pixelSize.width).rounded(), height: (n.height * pixelSize.height).rounded())
        delegate?.canvasCropChanged(pixelSize: size)
    }

    // MARK: - Keyboard

    /// Keys not covered by menu shortcuts. Returns `true` if handled.
    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        guard modifiers.isEmpty else { return false }
        if event.keyCode == 53 { // esc
            delegate?.canvasEscapePressed()
            return true
        }
        guard !isCropping else { return false }
        switch event.keyCode {
        case 49 where isShowingVideo: togglePlayback()            // space
        case 123, 116: delegate?.canvasNavigate(.previous)   // ←, page up
        case 124, 121: delegate?.canvasNavigate(.next)       // →, page down
        case 115: delegate?.canvasNavigate(.first)           // home
        case 119: delegate?.canvasNavigate(.last)            // end
        case 51, 117: delegate?.canvasDeleteRequested()      // delete, forward delete
        default: return false
        }
        return true
    }

    /// Keys pressed while the video player has focus bubble up here.
    override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    // MARK: - Drag & drop (into the window)

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingSource as? ImageDocumentView === documentView { return [] }
        return fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        delegate?.canvasReceivedDrop(urls)
        return true
    }
}

// MARK: - Scroll view

final class ZoomScrollView: NSScrollView {
    weak var canvas: ImageCanvasView?
    private var swipeAccumulator: CGFloat = 0
    private var swipeHandled = false
    private var lastWheelNavigation = Date.distantPast

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if canvas?.handleKey(event) != true { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { canvas?.toggleZoom(at: nil) }
    }

    override func magnify(with event: NSEvent) {
        guard canvas?.isCropping == false else { return }
        super.magnify(with: event)
        canvas?.magnificationChangedByGesture()
    }

    override func smartMagnify(with event: NSEvent) {
        guard let canvas, !canvas.isCropping else { return }
        canvas.toggleZoom(at: canvas.documentView.convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let canvas, canvas.hasImage, !canvas.isCropping else { return }

        // Mouse wheel (not a trackpad).
        if !event.hasPreciseScrollingDeltas {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.command) || modifiers.contains(.option) {
                let point = canvas.documentView.convert(event.locationInWindow, from: nil)
                canvas.zoom(by: pow(1.15, event.scrollingDeltaY), around: point)
                return
            }
            if canvas.contentFits, event.scrollingDeltaY != 0 {
                guard Date().timeIntervalSince(lastWheelNavigation) > 0.08 else { return }
                lastWheelNavigation = Date()
                canvas.delegate?.canvasNavigate(event.scrollingDeltaY > 0 ? .previous : .next)
                return
            }
            super.scrollWheel(with: event)
            return
        }

        // Trackpad: a horizontal two-finger swipe flips images when nothing can scroll.
        if canvas.contentFits {
            if event.phase == .began {
                swipeAccumulator = 0
                swipeHandled = false
            }
            if event.phase == .began || event.phase == .changed {
                if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                    swipeAccumulator += event.scrollingDeltaX
                }
                if !swipeHandled, abs(swipeAccumulator) > 50 {
                    swipeHandled = true
                    canvas.delegate?.canvasNavigate(swipeAccumulator > 0 ? .previous : .next)
                }
            }
            return
        }
        super.scrollWheel(with: event)
    }
}

/// Keeps the image centred when it is smaller than the visible area.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        if let documentView {
            let frame = documentView.frame
            if rect.width > frame.width { rect.origin.x = frame.minX - (rect.width - frame.width) / 2 }
            if rect.height > frame.height { rect.origin.y = frame.minY - (rect.height - frame.height) / 2 }
        }
        return rect
    }
}

// MARK: - Document view

/// Shows the bitmap through its layer (GPU-scaled, smooth at any zoom).
/// Drag to pan when zoomed in, or drag the photo out to Finder / Mail when it fits.
final class ImageDocumentView: NSView, NSDraggingSource {
    weak var canvas: ImageCanvasView?
    private var animatedView: NSImageView?
    private var dragOrigin: NSPoint?
    private var boundsOriginAtDragStart: NSPoint?
    private var startedFileDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .trilinear
        layer?.magnificationFilter = .linear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}

    private(set) var image: CGImage?

    func setImage(_ image: CGImage?, animated: NSImage?) {
        self.image = image
        layer?.contents = image
        if let animated {
            let view = animatedView ?? {
                let view = NSImageView(frame: bounds)
                view.autoresizingMask = [.width, .height]
                view.imageScaling = .scaleAxesIndependently
                view.animates = true
                view.isEditable = false
                view.unregisterDraggedTypes()
                addSubview(view)
                animatedView = view
                return view
            }()
            view.image = animated
        } else {
            animatedView?.removeFromSuperview()
            animatedView = nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The animated NSImageView must not swallow clicks.
        let hit = super.hitTest(point)
        return hit === animatedView ? self : hit
    }

    override func resetCursorRects() {
        if let canvas, canvas.hasImage, !canvas.contentFits {
            addCursorRect(visibleRect, cursor: .openHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(canvas?.scrollView)
        if event.clickCount == 2 {
            canvas?.toggleZoom(at: convert(event.locationInWindow, from: nil))
            return
        }
        dragOrigin = event.locationInWindow
        boundsOriginAtDragStart = enclosingScrollView?.contentView.bounds.origin
        startedFileDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, let start = dragOrigin, let originStart = boundsOriginAtDragStart,
              let scrollView = enclosingScrollView else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y

        if canvas.contentFits {
            // Drag the file out of the window.
            guard !startedFileDrag, hypot(dx, dy) > 4, let url = canvas.delegate?.canvasFileURL else { return }
            startedFileDrag = true
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let side: CGFloat = 96
            let size = canvas.pixelSize
            let scale = side / max(size.width, size.height, 1)
            let frameSize = NSSize(width: size.width * scale, height: size.height * scale)
            let location = convert(event.locationInWindow, from: nil)
            let frame = NSRect(x: location.x - frameSize.width / 2, y: location.y - frameSize.height / 2,
                               width: frameSize.width, height: frameSize.height)
            let preview = NSImage(size: frameSize)
            if let cg = image {
                preview.lockFocus()
                NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(origin: .zero, size: frameSize))
                preview.unlockFocus()
            }
            // Dragging frame is expressed in this view's (magnified) coordinates.
            let mag = scrollView.magnification
            item.setDraggingFrame(NSRect(x: frame.minX, y: frame.minY,
                                         width: frame.width / mag, height: frame.height / mag),
                                  contents: preview)
            beginDraggingSession(with: [item], event: event, source: self)
            return
        }

        // Pan.
        NSCursor.closedHand.set()
        let mag = scrollView.magnification
        let clip = scrollView.contentView
        var origin = NSPoint(x: originStart.x - dx / mag, y: originStart.y - dy / mag)
        origin = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        window?.invalidateCursorRects(for: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
