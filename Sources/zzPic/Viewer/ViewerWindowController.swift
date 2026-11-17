import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZZPicKit

/// One viewer window: browses the images of a folder.
@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    let model = ViewerModel()
    let canvas = ImageCanvasView()
    var onClose: ((ViewerWindowController) -> Void)?

    private var folder: URL?
    private var watcher: DirectoryWatcher?
    private var loadTask: Task<Void, Never>?
    private var spinnerTask: Task<Void, Never>?
    private var hudTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var rescanWork: DispatchWorkItem?

    /// Undo history of file operations; groups are opened explicitly by `registerUndo`.
    let undoStack: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        manager.levelsOfUndo = 50
        return manager
    }()

    var isEmpty: Bool { model.files.isEmpty && folder == nil }

    var sortOrder: ImageSortOrder {
        get { ImageSortOrder(rawValue: UserDefaults.standard.string(forKey: "sortOrder") ?? "") ?? .name }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "sortOrder") }
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 560, height: 420)
        window.toolbarStyle = .unified
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.backgroundColor = .zzCanvas
        window.title = "zzPic"
        window.center()
        super.init(window: window)

        window.delegate = self
        canvas.delegate = self

        let host = NSHostingView(rootView: ViewerRootView(model: model, canvas: canvas, actions: self))
        host.sizingOptions = []
        window.contentView = host

        let toolbar = NSToolbar(identifier: "ViewerToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar

        windowFrameAutosaveName = "ViewerWindow"
        window.initialFirstResponder = canvas.scrollView
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(canvas.scrollView)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoStack
    }

    func windowWillClose(_ notification: Notification) {
        loadTask?.cancel()
        canvas.stopVideo()
        watcher = nil
        onClose?(self)
    }

    // MARK: - Opening

    func open(_ url: URL) {
        let url = url.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        if !isDirectory.boolValue, !FolderScanner.isMediaFile(url) {
            let alert = NSAlert()
            alert.messageText = LF("“%@” isn’t a file zzPic can open.", url.lastPathComponent)
            alert.informativeText = L("zzPic opens common image formats (JPEG, PNG, HEIC, GIF, TIFF, WebP, camera RAW) and videos (MOV, MP4, M4V).")
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }

        if model.isCropping { cancelCrop() }
        let dir = isDirectory.boolValue ? url : url.deletingLastPathComponent()
        folder = dir
        watcher = DirectoryWatcher(url: dir) { [weak self] in self?.scheduleRescan() }

        var files = FolderScanner.scan(folder: dir, sortedBy: sortOrder)
        var index = 0
        if !isDirectory.boolValue {
            if let i = files.firstIndex(ofFile: url) {
                index = i
            } else {
                // e.g. a hidden file: show it anyway.
                files.append(url)
                index = files.count - 1
            }
        }
        model.files = files
        model.index = index
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        showCurrent()
    }

    // MARK: - Displaying

    func showCurrent() {
        loadTask?.cancel()
        spinnerTask?.cancel()
        model.showSpinner = false
        updateTitle()

        guard let url = model.current else {
            model.loaded = nil
            model.loadError = nil
            canvas.display(nil)
            updateTitle()
            return
        }

        if FolderScanner.isVideoFile(url) {
            presentVideo(url)
            return
        }

        if let cached = ImageLoader.shared.cachedImage(for: url) {
            present(cached)
            return
        }

        spinnerTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.model.showSpinner = true
        }
        loadTask = Task { [weak self] in
            do {
                let image = try await ImageLoader.shared.load(url)
                guard let self, !Task.isCancelled, self.model.current?.isSameFile(as: url) == true else { return }
                self.present(image)
            } catch {
                guard let self, !Task.isCancelled, self.model.current?.isSameFile(as: url) == true else { return }
                self.spinnerTask?.cancel()
                self.model.showSpinner = false
                self.model.loaded = nil
                self.model.loadError = error.localizedDescription
                self.canvas.display(nil)
                self.updateTitle()
            }
        }
    }

    private func present(_ image: LoadedImage) {
        spinnerTask?.cancel()
        model.showSpinner = false
        model.loadError = nil
        model.loaded = image
        canvas.display(image)
        updateTitle()
        loadMetadata()
        prefetchNeighbours()
    }

    private func presentVideo(_ url: URL) {
        model.loaded = nil
        model.loadError = nil
        canvas.displayVideo(url)
        updateTitle()
        loadMetadata()
        prefetchNeighbours()
        loadTask = Task { [weak self] in
            let info = try? await VideoInfo.load(url)
            guard let self, !Task.isCancelled, self.model.current?.isSameFile(as: url) == true else { return }
            self.model.video = info
            self.canvas.setVideoSize(info?.pixelSize)
            self.updateTitle()
            self.loadMetadata()
        }
    }

    private func prefetchNeighbours() {
        let files = model.files
        guard files.count > 1 else { return }
        let n = files.count
        let neighbours = [1, -1, 2].map { files[(model.index + $0 + n) % n] }.filter { !FolderScanner.isVideoFile($0) }
        ImageLoader.shared.prefetch(neighbours)
    }

    func updateTitle() {
        guard let window else { return }
        if let url = model.current {
            window.title = url.lastPathComponent
            window.representedURL = url
            var parts = [LF("%ld of %ld", model.index + 1, model.files.count)]
            if let image = model.currentImage {
                parts.append("\(Int(image.pixelSize.width)) × \(Int(image.pixelSize.height))")
                parts.append(ByteCountFormatter.string(fromByteCount: image.fileSize, countStyle: .file))
            } else if let video = model.currentVideo {
                parts.append("\(Int(video.pixelSize.width)) × \(Int(video.pixelSize.height))")
                parts.append(video.durationText)
                parts.append(ByteCountFormatter.string(fromByteCount: video.fileSize, countStyle: .file))
            }
            window.subtitle = parts.joined(separator: "  ·  ")
        } else {
            window.title = folder?.lastPathComponent ?? "zzPic"
            window.representedURL = nil
            window.subtitle = folder == nil ? "" : L("No images")
        }
        updateShareItem()
        // Images load asynchronously: refresh enabled states without waiting for the next event.
        window.toolbar?.validateVisibleItems()
    }

    func loadMetadata() {
        metadataTask?.cancel()
        guard model.showInspector, let url = model.current else { return }
        let video = model.currentIsVideo ? model.currentVideo : nil
        if model.currentIsVideo, video == nil {
            model.metadata = [ImageMetadata.generalSection(for: url)]   // details follow once loaded
            return
        }
        metadataTask = Task { [weak self] in
            let sections = await Task.detached(priority: .utility) {
                video.map(ImageMetadata.sections(for:)) ?? ImageMetadata.sections(for: url)
            }.value
            guard let self, !Task.isCancelled, self.model.current?.isSameFile(as: url) == true else { return }
            self.model.metadata = sections
        }
    }

    // MARK: - Folder changes

    private func scheduleRescan() {
        rescanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rescan() }
        rescanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func rescan(select preferred: URL? = nil) {
        guard let folder else { return }
        let order = sortOrder
        Task { [weak self] in
            let files = await Task.detached(priority: .userInitiated) {
                FolderScanner.scan(folder: folder, sortedBy: order)
            }.value
            self?.apply(scan: files, preferred: preferred)
        }
    }

    private func apply(scan files: [URL], preferred: URL?) {
        guard !model.isCropping else { return }
        let previous = model.current
        let previousIndex = model.index
        model.files = files

        if let target = preferred ?? previous, let i = files.firstIndex(ofFile: target) {
            model.index = i
        } else {
            model.index = max(0, min(previousIndex, files.count - 1))
        }

        let current = model.current
        let sameFile = current != nil && previous != nil && current!.isSameFile(as: previous!)
        if !sameFile {
            showCurrent()
        } else if let current, let loaded = model.currentImage {
            let date = (try? current.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if date != loaded.modificationDate {
                fileDidChange(current)
            } else {
                updateTitle()
            }
        } else {
            updateTitle()
        }
    }

    /// Something changed `url` on disk: drop caches and redisplay.
    func fileDidChange(_ url: URL) {
        ImageLoader.shared.invalidate(url)
        ThumbnailProvider.shared.invalidate(url)
        model.revisions[url.fileKey, default: 0] += 1
        if model.current?.isSameFile(as: url) == true { showCurrent() }
    }

    // MARK: - Feedback

    func showToast(_ message: String, symbol: String, undo: Bool = false) {
        let toast = Toast(message: message, symbol: symbol, canUndo: undo)
        model.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo ? 5 : 2.5))
            guard !Task.isCancelled, self?.model.toast?.id == toast.id else { return }
            self?.model.toast = nil
        }
    }

    func showError(_ error: Error) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    private func showZoomHUD(_ text: String) {
        model.zoomHUD = text
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.model.zoomHUD = nil
        }
    }
}

// MARK: - Canvas delegate

extension ViewerWindowController: ImageCanvasDelegate {
    var canvasFileURL: URL? { model.current }

    func canvasNavigate(_ step: NavigationStep) { go(step) }

    func canvasDeleteRequested() { moveToTrash(nil) }

    func canvasEscapePressed() {
        if model.isCropping {
            cancelCrop()
        } else if window?.styleMask.contains(.fullScreen) == true {
            window?.toggleFullScreen(nil)
        }
    }

    func canvasZoomChanged(percent: Int, isFit: Bool, userInitiated: Bool) {
        guard userInitiated, !model.isCropping else { return }
        showZoomHUD(isFit ? LF("Fit · %ld%%", percent) : "\(percent)%")
    }

    func canvasCropChanged(pixelSize: CGSize) {
        model.cropPixelSize = pixelSize
    }

    func canvasReceivedDrop(_ urls: [URL]) {
        open(urls: urls)
    }
}

// MARK: - SwiftUI actions

extension ViewerWindowController: ViewerActions {
    func openDocument() {
        openDocument(nil)
    }

    func open(urls: [URL]) {
        guard let first = urls.first else { return }
        open(first)
        // Extra files open in their own windows.
        for url in urls.dropFirst() {
            (NSApp.delegate as? AppDelegate)?.openViewer(url)
        }
    }

    func select(index: Int) {
        guard model.files.indices.contains(index), !model.isCropping else { return }
        model.index = index
        showCurrent()
    }

    func undo() {
        model.toast = nil
        window?.undoManager?.undo()
    }
}
