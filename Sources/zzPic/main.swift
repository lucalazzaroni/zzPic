import AppKit

MainActor.assumeIsolated {
    // Instantiate our document controller first so it becomes `NSDocumentController.shared`
    // (it powers File ▸ Open Recent).
    _ = RecentsDocumentController()

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
