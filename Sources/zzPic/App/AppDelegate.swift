import AppKit
import UniformTypeIdentifiers
import ZZPicKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let repositoryURL = URL(string: "https://github.com/lucalazzaroni/zzPic")!

    private var controllers: [ViewerWindowController] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenuBuilder.build()
        FileOps.clearBackups()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Files opened from Finder arrive through `application(_:open:)`; only show an
        // empty window when the app was launched on its own.
        DispatchQueue.main.async {
            if self.controllers.isEmpty { self.newViewer().showWindow(nil) }
        }
        #if DEBUG
        installDebugAutomation()
        #endif
    }

    #if DEBUG
    /// Debug builds only: lets scripts trigger actions, e.g.
    /// `swift Scripts/debug-send.swift nextImage:`
    private func installDebugAutomation() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("io.github.lucalazzaroni.zzPic.debug"), object: nil, queue: .main
        ) { note in
            guard let command = note.object as? String else { return }
            MainActor.assumeIsolated {
                let controller = NSApp.keyWindow?.windowController as? ViewerWindowController
                    ?? NSApp.windows.compactMap { $0.windowController as? ViewerWindowController }.first
                switch command {
                case "applyCrop": controller?.applyCrop(asCopy: false)
                case "applyCropCopy": controller?.applyCrop(asCopy: true)
                case "square": controller?.model.cropAspect = .square
                case "resizeHalf":
                    if let size = controller?.model.currentImage?.pixelSize {
                        controller?.applyResize(width: Int(size.width / 2), height: Int(size.height / 2), asCopy: false)
                    }
                case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                case "light": NSApp.appearance = NSAppearance(named: .aqua)
                case "undo": controller?.window?.undoManager?.undo()
                case "redo": controller?.window?.undoManager?.redo()
                default:
                    let selector = Selector(command)
                    if let controller, controller.responds(to: selector) {
                        NSApp.sendAction(selector, to: controller, from: nil)
                    } else {
                        NSApp.sendAction(selector, to: nil, from: nil)
                    }
                }
            }
        }
    }
    #endif

    func application(_ sender: NSApplication, open urls: [URL]) {
        urls.forEach(openViewer)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newViewer().showWindow(nil) }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Windows

    func openViewer(_ url: URL) {
        let controller = controllers.first(where: { $0.isEmpty }) ?? newViewer()
        controller.open(url)
        controller.showWindow(nil)
    }

    @discardableResult
    func newViewer() -> ViewerWindowController {
        let controller = ViewerWindowController()
        if let previous = NSApp.keyWindow ?? controllers.last?.window, let window = controller.window {
            let topLeft = NSPoint(x: previous.frame.minX, y: previous.frame.maxY)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: topLeft))
        }
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        return controller
    }

    // MARK: - Actions

    @objc func openDocument(_ sender: Any?) {
        OpenPanel.run(attachedTo: nil) { [weak self] urls in
            urls.forEach { self?.openViewer($0) }
        }
    }

    @objc func showAboutPanel(_ sender: Any?) {
        let credits = NSMutableAttributedString(
            string: L("A fast, minimal image viewer for macOS.") + "\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        credits.append(NSAttributedString(
            string: "github.com/lucalazzaroni/zzPic",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: Self.repositoryURL]
        ))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }

    @objc func openRepository(_ sender: Any?) {
        NSWorkspace.shared.open(Self.repositoryURL)
    }
}

/// Routes File ▸ Open Recent through our own window logic (zzPic has no `NSDocument`s).
final class RecentsDocumentController: NSDocumentController {
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        MainActor.assumeIsolated {
            (NSApp.delegate as? AppDelegate)?.openViewer(url)
        }
        completionHandler(nil, false, nil)
    }
}

enum OpenPanel {
    @MainActor
    static func run(attachedTo window: NSWindow?, completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie, .folder]
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L("Choose an image or video, or a folder")
        panel.prompt = L("Open")
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK { completion(panel.urls) }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}
