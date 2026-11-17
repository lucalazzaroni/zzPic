import AppKit

/// Interactive crop rectangle drawn above the fitted image.
/// The selection is stored normalized (0…1, origin top-left) so it survives window resizes.
final class CropOverlayView: NSView {
    private enum Handle {
        case none, move, create
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Where the image is drawn, in this view's (flipped) coordinates.
    var imageRect: CGRect = .zero {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    private(set) var normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var onChange: ((CGRect) -> Void)?

    /// Width / height constraint, nil for freeform.
    private var aspect: CGFloat?
    private var active: Handle = .none
    private var startRect: CGRect = .zero
    private var startPoint: CGPoint = .zero
    private let minimumSide: CGFloat = 16

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry

    private var cropRect: CGRect {
        CGRect(x: imageRect.minX + normalizedRect.minX * imageRect.width,
               y: imageRect.minY + normalizedRect.minY * imageRect.height,
               width: normalizedRect.width * imageRect.width,
               height: normalizedRect.height * imageRect.height)
    }

    private func setCropRect(_ rect: CGRect) {
        guard imageRect.width > 0, imageRect.height > 0 else { return }
        var n = CGRect(x: (rect.minX - imageRect.minX) / imageRect.width,
                       y: (rect.minY - imageRect.minY) / imageRect.height,
                       width: rect.width / imageRect.width,
                       height: rect.height / imageRect.height)
        n = n.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !n.isNull, n.width > 0, n.height > 0 else { return }
        normalizedRect = n
        needsDisplay = true
        onChange?(n)
    }

    func reset(aspect: CGFloat?) {
        self.aspect = aspect
        normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let aspect { setCropRect(largestRect(aspect: aspect)) } else { onChange?(normalizedRect) }
        needsDisplay = true
    }

    func setAspect(_ aspect: CGFloat?) {
        self.aspect = aspect
        if let aspect { setCropRect(largestRect(aspect: aspect)) }
    }

    private func largestRect(aspect: CGFloat) -> CGRect {
        let r = imageRect
        var w = r.width, h = r.height
        if w / h > aspect { w = h * aspect } else { h = w / aspect }
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, imageRect.minX), imageRect.maxX),
                y: min(max(p.y, imageRect.minY), imageRect.maxY))
    }

    private func handle(at p: CGPoint) -> Handle {
        let r = cropRect
        let t: CGFloat = 10
        let nearL = abs(p.x - r.minX) < t, nearR = abs(p.x - r.maxX) < t
        let nearT = abs(p.y - r.minY) < t, nearB = abs(p.y - r.maxY) < t
        let withinX = p.x > r.minX - t && p.x < r.maxX + t
        let withinY = p.y > r.minY - t && p.y < r.maxY + t
        if nearL && nearT { return .topLeft }
        if nearR && nearT { return .topRight }
        if nearL && nearB { return .bottomLeft }
        if nearR && nearB { return .bottomRight }
        if nearL && withinY { return .left }
        if nearR && withinY { return .right }
        if nearT && withinX { return .top }
        if nearB && withinX { return .bottom }
        if r.contains(p) { return .move }
        return .create
    }

    /// Rectangle spanned by a fixed anchor and a moving corner, honouring the aspect ratio.
    private func rect(anchor a: CGPoint, moving m: CGPoint, minimum: CGFloat) -> CGRect {
        var w = abs(m.x - a.x), h = abs(m.y - a.y)
        if let aspect {
            if h == 0 || w / h > aspect { w = h * aspect } else { h = w / aspect }
            if w < minimum || h < minimum {
                if aspect >= 1 { h = minimum; w = h * aspect } else { w = minimum; h = w / aspect }
            }
        } else {
            w = max(w, minimum)
            h = max(h, minimum)
        }
        let x = m.x < a.x ? a.x - w : a.x
        let y = m.y < a.y ? a.y - h : a.y
        return constrained(CGRect(x: x, y: y, width: w, height: h))
    }

    /// Slides a rectangle back inside the image (and shrinks it if it is too big).
    private func constrained(_ rect: CGRect) -> CGRect {
        var r = rect
        r.size.width = min(r.width, imageRect.width)
        r.size.height = min(r.height, imageRect.height)
        r.origin.x = min(max(r.minX, imageRect.minX), imageRect.maxX - r.width)
        r.origin.y = min(max(r.minY, imageRect.minY), imageRect.maxY - r.height)
        return r
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        active = handle(at: p)
        startRect = cropRect
        startPoint = clamp(p)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        let p = clamp(raw)
        let dx = raw.x - startPoint.x, dy = raw.y - startPoint.y
        let s = startRect, ir = imageRect
        var r = s

        switch active {
        case .none:
            return
        case .move:
            r.origin.x = min(max(ir.minX, s.minX + dx), ir.maxX - s.width)
            r.origin.y = min(max(ir.minY, s.minY + dy), ir.maxY - s.height)
        case .create:
            r = rect(anchor: startPoint, moving: p, minimum: 1)
        case .topLeft:
            r = rect(anchor: CGPoint(x: s.maxX, y: s.maxY), moving: p, minimum: minimumSide)
        case .topRight:
            r = rect(anchor: CGPoint(x: s.minX, y: s.maxY), moving: p, minimum: minimumSide)
        case .bottomLeft:
            r = rect(anchor: CGPoint(x: s.maxX, y: s.minY), moving: p, minimum: minimumSide)
        case .bottomRight:
            r = rect(anchor: CGPoint(x: s.minX, y: s.minY), moving: p, minimum: minimumSide)
        case .left, .right:
            let x = active == .left ? min(p.x, s.maxX - minimumSide) : max(p.x, s.minX + minimumSide)
            let anchorX = active == .left ? s.maxX : s.minX
            var w = abs(anchorX - x)
            var h = s.height
            if let aspect {
                h = w / aspect
                let maxH = 2 * min(s.midY - ir.minY, ir.maxY - s.midY)
                if h > maxH { h = maxH; w = h * aspect }
            }
            r = CGRect(x: active == .left ? anchorX - w : anchorX, y: aspect == nil ? s.minY : s.midY - h / 2,
                       width: w, height: h)
        case .top, .bottom:
            let y = active == .top ? min(p.y, s.maxY - minimumSide) : max(p.y, s.minY + minimumSide)
            let anchorY = active == .top ? s.maxY : s.minY
            var h = abs(anchorY - y)
            var w = s.width
            if let aspect {
                w = h * aspect
                let maxW = 2 * min(s.midX - ir.minX, ir.maxX - s.midX)
                if w > maxW { w = maxW; h = w / aspect }
            }
            r = CGRect(x: aspect == nil ? s.minX : s.midX - w / 2, y: active == .top ? anchorY - h : anchorY,
                       width: w, height: h)
        }
        setCropRect(r)
    }

    override func mouseUp(with event: NSEvent) {
        // A simple click outside the selection must not collapse it.
        if active == .create, cropRect.width < 4 || cropRect.height < 4 {
            setCropRect(startRect)
        }
        active = .none
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Cursors

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard active == .none else { return }
        cursor(for: handle(at: convert(event.locationInWindow, from: nil))).set()
    }

    private func cursor(for handle: Handle) -> NSCursor {
        if #available(macOS 15.0, *) {
            switch handle {
            case .left: return .frameResize(position: .left, directions: .all)
            case .right: return .frameResize(position: .right, directions: .all)
            case .top: return .frameResize(position: .top, directions: .all)
            case .bottom: return .frameResize(position: .bottom, directions: .all)
            case .topLeft: return .frameResize(position: .topLeft, directions: .all)
            case .topRight: return .frameResize(position: .topRight, directions: .all)
            case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
            case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
            case .move: return .openHand
            case .create, .none: return .crosshair
            }
        }
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .move: return .openHand
        default: return .crosshair
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard imageRect.width > 0 else { return }
        let r = cropRect

        // Dim everything outside the selection.
        NSColor.black.withAlphaComponent(0.55).setFill()
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: r))
        dim.windingRule = .evenOdd
        dim.fill()

        // Rule-of-thirds grid while adjusting.
        if active != .none {
            NSColor.white.withAlphaComponent(0.45).setStroke()
            let grid = NSBezierPath()
            grid.lineWidth = 0.75
            for i in 1...2 {
                let x = r.minX + r.width * CGFloat(i) / 3
                let y = r.minY + r.height * CGFloat(i) / 3
                grid.move(to: CGPoint(x: x, y: r.minY)); grid.line(to: CGPoint(x: x, y: r.maxY))
                grid.move(to: CGPoint(x: r.minX, y: y)); grid.line(to: CGPoint(x: r.maxX, y: y))
            }
            grid.stroke()
        }

        // Border.
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        // Corner and edge handles.
        let t: CGFloat = 4
        let l = min(24, r.width / 2, r.height / 2)
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        ctx?.setShadow(offset: .zero, blur: 3, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        NSColor.white.setFill()
        let bars: [CGRect] = [
            // corners
            CGRect(x: r.minX - t, y: r.minY - t, width: l + t, height: t), CGRect(x: r.minX - t, y: r.minY - t, width: t, height: l + t),
            CGRect(x: r.maxX - l, y: r.minY - t, width: l + t, height: t), CGRect(x: r.maxX, y: r.minY - t, width: t, height: l + t),
            CGRect(x: r.minX - t, y: r.maxY, width: l + t, height: t), CGRect(x: r.minX - t, y: r.maxY - l, width: t, height: l + t),
            CGRect(x: r.maxX - l, y: r.maxY, width: l + t, height: t), CGRect(x: r.maxX, y: r.maxY - l, width: t, height: l + t),
            // edges
            CGRect(x: r.midX - l / 2, y: r.minY - t, width: l, height: t), CGRect(x: r.midX - l / 2, y: r.maxY, width: l, height: t),
            CGRect(x: r.minX - t, y: r.midY - l / 2, width: t, height: l), CGRect(x: r.maxX, y: r.midY - l / 2, width: t, height: l),
        ]
        for bar in bars { NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill() }
        ctx?.restoreGState()
    }
}
