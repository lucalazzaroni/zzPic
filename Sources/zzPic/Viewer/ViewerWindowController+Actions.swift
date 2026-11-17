import AppKit
import UniformTypeIdentifiers
import ZZPicKit

/// Menu / toolbar commands. They travel through the responder chain, so they only
/// apply to the key viewer window.
extension ViewerWindowController {

    // MARK: - Navigation

    func go(_ step: NavigationStep) {
        guard !model.files.isEmpty, !model.isCropping else { return }
        let n = model.files.count
        switch step {
        case .previous: model.index = (model.index - 1 + n) % n
        case .next: model.index = (model.index + 1) % n
        case .first: model.index = 0
        case .last: model.index = n - 1
        }
        showCurrent()
    }

    @objc func previousImage(_ sender: Any?) { go(.previous) }
    @objc func nextImage(_ sender: Any?) { go(.next) }
    @objc func firstImage(_ sender: Any?) { go(.first) }
    @objc func lastImage(_ sender: Any?) { go(.last) }

    @objc func openDocument(_ sender: Any?) {
        OpenPanel.run(attachedTo: window) { [weak self] urls in self?.open(urls: urls) }
    }

    // MARK: - Zoom

    @objc func zoomIn(_ sender: Any?) { canvas.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { canvas.zoomOut() }
    @objc func actualSize(_ sender: Any?) { canvas.actualSize() }
    @objc func zoomToFit(_ sender: Any?) { canvas.zoomToFit() }

    // MARK: - View options

    @objc func toggleFilmstrip(_ sender: Any?) {
        model.showFilmstrip.toggle()
    }

    @objc func toggleInspector(_ sender: Any?) {
        model.showInspector.toggle()
        if model.showInspector { model.metadata = [] }
        loadMetadata()
    }

    @objc func changeSortOrder(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let order = ImageSortOrder(rawValue: raw) else { return }
        sortOrder = order
        rescan(select: model.current)
    }

    // MARK: - Editing

    @objc func rotateLeft(_ sender: Any?) {
        performEdit(.rotate(clockwise: false), asCopy: false, actionName: L("Rotate"))
    }

    @objc func rotateRight(_ sender: Any?) {
        performEdit(.rotate(clockwise: true), asCopy: false, actionName: L("Rotate"))
    }

    @objc func toggleCrop(_ sender: Any?) {
        if model.isCropping { cancelCrop() } else { beginCrop() }
    }

    func beginCrop() {
        guard let image = model.currentImage, !image.isAnimated else { return }
        model.toast = nil
        model.cropAspect = .free
        model.cropPortrait = image.pixelSize.height > image.pixelSize.width
        model.cropPixelSize = image.pixelSize
        model.isCropping = true
        // Let SwiftUI swap the filmstrip for the crop bar first, so the image is fitted to the final size.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.isCropping else { return }
            self.canvas.beginCrop(aspect: nil)
        }
    }

    func cancelCrop() {
        model.isCropping = false
        canvas.endCrop()
    }

    func applyCrop(asCopy: Bool) {
        let rect = canvas.cropNormalizedRect
        cancelCrop()
        let isWholeImage = rect.minX < 0.0005 && rect.minY < 0.0005 && rect.width > 0.999 && rect.height > 0.999
        guard !isWholeImage else { return }
        performEdit(.crop(rect), asCopy: asCopy, actionName: L("Crop"))
    }

    func cropAspectChanged() {
        guard let image = model.currentImage else { return }
        canvas.setCropAspect(model.cropAspect.ratio(for: image.pixelSize, portrait: model.cropPortrait))
    }

    @objc func resizeImage(_ sender: Any?) {
        guard let image = model.currentImage, !image.isAnimated else { return }
        model.resizeRequest = ResizeRequest(pixelSize: image.pixelSize, canOverwrite: model.canOverwrite)
    }

    func applyResize(width: Int, height: Int, asCopy: Bool) {
        performEdit(.resize(width: width, height: height), asCopy: asCopy, actionName: L("Resize"))
    }

    /// Renders the edit in the background, then either replaces the file (undoable)
    /// or saves it next to the original as "name copy.ext".
    func performEdit(_ operation: EditOperation, asCopy: Bool, actionName: String) {
        guard let url = model.current, let image = model.currentImage, !image.isAnimated, !model.isBusy else {
            NSSound.beep()
            return
        }
        let writable = ImageEditor.canWrite(type: image.typeIdentifier)
        guard asCopy || writable else { NSSound.beep(); return }
        let outputType = writable ? image.typeIdentifier! : UTType.jpeg.identifier
        let outputExtension = writable ? url.pathExtension : "jpg"
        let temp = FileOps.temporaryURL(near: url, pathExtension: outputExtension)

        model.isBusy = true
        Task { [weak self] in
            let failure: Error? = await Task.detached(priority: .userInitiated) {
                do {
                    try ImageEditor.render(operation, source: url, output: temp, outputType: outputType)
                    return nil
                } catch {
                    return error
                }
            }.value
            guard let self else { return }
            self.model.isBusy = false
            if let failure {
                try? FileManager.default.removeItem(at: temp)
                self.showError(failure)
                return
            }
            do {
                if asCopy {
                    let destination = FileOps.uniqueCopyURL(for: url, pathExtension: outputExtension)
                    try FileManager.default.moveItem(at: temp, to: destination)
                    self.registerUndo(actionName) { $0.performTrash(destination, actionName: actionName, announce: false) }
                    self.showToast(LF("Saved as “%@”", destination.lastPathComponent), symbol: "checkmark.circle", undo: true)
                    self.rescan(select: destination)
                } else {
                    let backup = try FileOps.makeBackup(of: url)
                    try FileOps.replace(url, with: temp)
                    self.registerRestore(of: url, from: backup, actionName: actionName)
                    self.fileDidChange(url)
                    switch operation {
                    case .crop: self.showToast(L("Image cropped"), symbol: "crop", undo: true)
                    case .resize: self.showToast(L("Image resized"), symbol: "arrow.up.left.and.arrow.down.right", undo: true)
                    case .rotate: break
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: temp)
                self.showError(error)
            }
        }
    }

    // MARK: - File operations

    @objc func duplicateImage(_ sender: Any?) {
        guard let url = model.current else { return }
        let destination = FileOps.uniqueCopyURL(for: url)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            registerUndo(L("Duplicate")) { $0.performTrash(destination, actionName: L("Duplicate"), announce: false) }
            showToast(LF("Duplicated as “%@”", destination.lastPathComponent), symbol: "plus.square.on.square", undo: true)
            rescan()
        } catch {
            showError(error)
        }
    }

    @objc func moveToTrash(_ sender: Any?) {
        guard let url = model.current, !model.isCropping else { return }
        performTrash(url, actionName: L("Move to Trash"), announce: true)
    }

    func performTrash(_ url: URL, actionName: String, announce: Bool) {
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            removeFromList(url)
            if let trashed = resulting as URL? {
                registerUndo(actionName) { $0.performRestore(from: trashed, to: url, actionName: actionName) }
            }
            if announce {
                showToast(LF("“%@” moved to the Trash", url.lastPathComponent), symbol: "trash", undo: true)
            }
        } catch {
            confirmPermanentDelete(url)
        }
    }

    private func performRestore(from trashed: URL, to original: URL, actionName: String) {
        do {
            try FileManager.default.moveItem(at: trashed, to: original)
            registerUndo(actionName) { $0.performTrash(original, actionName: actionName, announce: false) }
            rescan(select: original)
        } catch {
            showError(error)
        }
    }

    /// Volumes without a Trash (network shares, some USB drives): ask before deleting for good.
    private func confirmPermanentDelete(_ url: URL) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = LF("“%@” can’t be moved to the Trash.", url.lastPathComponent)
        alert.informativeText = L("Do you want to delete it immediately? This can’t be undone.")
        let delete = alert.addButton(withTitle: L("Delete"))
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: L("Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            do {
                try FileManager.default.removeItem(at: url)
                self?.removeFromList(url)
            } catch {
                self?.showError(error)
            }
        }
    }

    private func removeFromList(_ url: URL) {
        guard let i = model.files.firstIndex(ofFile: url) else { return }
        let wasCurrent = i == model.index
        model.files.remove(at: i)
        if i < model.index {
            model.index -= 1
            updateTitle()
        } else if wasCurrent {
            model.index = max(0, min(i, model.files.count - 1))
            showCurrent()
        } else {
            updateTitle()
        }
    }

    @objc func showInFinder(_ sender: Any?) {
        guard let url = model.current else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func openInPreview(_ sender: Any?) {
        let editor = model.currentIsVideo ? "com.apple.QuickTimePlayerX" : "com.apple.Preview"
        guard let url = model.current,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor) else { return }
        if model.currentIsVideo { canvas.stopVideo() }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func copy(_ sender: Any?) {
        guard let url = model.current else { return }
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if !model.currentIsVideo, let type = UTType(filenameExtension: url.pathExtension),
           let data = try? Data(contentsOf: url) {
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
        if let image = model.currentImage?.image {
            let provider = ImagePasteboardProvider(image: image)
            item.setDataProvider(provider, forTypes: [.png, .tiff])
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
        showToast(L("Copied"), symbol: "doc.on.doc")
    }

    @objc func printImage(_ sender: Any?) {
        guard let url = model.current, let window else { return }
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { try? ImageEditor.uprightImage(at: url) }.value
            guard let self, let image else { NSSound.beep(); return }
            PrintImageView.print(image, title: url.deletingPathExtension().lastPathComponent, window: window)
            _ = self
        }
    }

    // MARK: - Undo

    func registerUndo(_ actionName: String, _ handler: @escaping (ViewerWindowController) -> Void) {
        // Each file operation is its own undo step, even when it completes asynchronously.
        undoStack.beginUndoGrouping()
        undoStack.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.model.toast = nil
                handler(target)
            }
        }
        undoStack.setActionName(actionName)
        undoStack.endUndoGrouping()
    }

    /// Undo of an overwrite swaps the file with its backup; redo swaps it back.
    private func registerRestore(of url: URL, from backup: URL, actionName: String) {
        registerUndo(actionName) { controller in
            do {
                let newBackup = try FileOps.makeBackup(of: url)
                try FileOps.replace(url, with: backup)
                controller.registerRestore(of: url, from: newBackup, actionName: actionName)
                controller.fileDidChange(url)
            } catch {
                controller.showError(error)
            }
        }
    }
}

// MARK: - Validation

extension ViewerWindowController: NSMenuItemValidation, NSToolbarItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleFilmstrip(_:)):
            item.title = model.showFilmstrip ? L("Hide Filmstrip") : L("Show Filmstrip")
            return true
        case #selector(toggleInspector(_:)):
            item.title = model.showInspector ? L("Hide Info") : L("Show Info")
            return true
        case #selector(toggleCrop(_:)):
            item.title = model.isCropping ? L("Cancel Crop") : L("Crop…")
            return canPerform(item.action)
        case #selector(openInPreview(_:)):
            item.title = model.currentIsVideo ? L("Open in QuickTime Player") : L("Edit in Preview")
            return canPerform(item.action)
        case #selector(changeSortOrder(_:)):
            item.state = (item.representedObject as? String) == sortOrder.rawValue ? .on : .off
            return !model.isCropping
        default:
            return canPerform(item.action)
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        canPerform(item.action)
    }

    private func canPerform(_ action: Selector?) -> Bool {
        let hasFile = model.current != nil
        let cropping = model.isCropping
        switch action {
        case #selector(previousImage(_:)), #selector(nextImage(_:)),
             #selector(firstImage(_:)), #selector(lastImage(_:)):
            return !cropping && model.files.count > 1
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(actualSize(_:)), #selector(zoomToFit(_:)):
            return model.currentImage != nil && !cropping
        case #selector(rotateLeft(_:)), #selector(rotateRight(_:)):
            return model.canOverwrite && !cropping && !model.isBusy
        case #selector(toggleCrop(_:)):
            return cropping || (model.canEdit && !model.isBusy)
        case #selector(resizeImage(_:)):
            return model.canEdit && !cropping && !model.isBusy
        case #selector(printImage(_:)):
            return model.currentImage != nil && !cropping
        case #selector(duplicateImage(_:)), #selector(moveToTrash(_:)), #selector(showInFinder(_:)),
             #selector(openInPreview(_:)), #selector(copy(_:)):
            return hasFile && !cropping
        case #selector(toggleInspector(_:)):
            return true
        default:
            return true
        }
    }
}

/// Produces PNG / TIFF data for the clipboard only when another app asks for it.
private final class ImagePasteboardProvider: NSObject, NSPasteboardItemDataProvider {
    let image: CGImage
    init(image: CGImage) { self.image = image }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        let rep = NSBitmapImageRep(cgImage: image)
        let data = type == .png ? rep.representation(using: .png, properties: [:]) : rep.tiffRepresentation
        if let data { item.setData(data, forType: type) }
    }
}
