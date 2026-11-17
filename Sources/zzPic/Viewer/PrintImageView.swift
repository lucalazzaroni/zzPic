import AppKit
import ZZPicKit

/// Prints one image, scaled to fit the printable area of the page and centred.
final class PrintImageView: NSView {
    private let image: NSImage

    @MainActor
    static func print(_ cgImage: CGImage, title: String, window: NSWindow) {
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.orientation = cgImage.width > cgImage.height ? .landscape : .portrait
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0

        let view = PrintImageView(image: image, paperSize: info.paperSize)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling,
                                                .showsPreview, .showsCopies])
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private init(image: NSImage, paperSize: NSSize) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: paperSize))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func matchPaper() {
        if let info = NSPrintOperation.current?.printInfo, frame.size != info.paperSize {
            setFrameSize(info.paperSize)
        }
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        matchPaper()
        range.pointee = NSRange(location: 1, length: 1)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        matchPaper()
        return bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        let info = NSPrintOperation.current?.printInfo
        let printable = (info?.imageablePageBounds ?? bounds).insetBy(dx: 18, dy: 18)
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(printable.width / size.width, printable.height / size.height)
        let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
        let rect = NSRect(x: printable.midX - drawSize.width / 2, y: printable.midY - drawSize.height / 2,
                          width: drawSize.width, height: drawSize.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
    }
}
