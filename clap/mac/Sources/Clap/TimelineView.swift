import AppKit

protocol TimelineViewDelegate: AnyObject {
    func timeline(_ view: TimelineView, didSeekTo t: Double)
    func timeline(_ view: TimelineView, didSelectSegment id: UUID?)
    func timeline(_ view: TimelineView, didResizeSegment id: UUID, newStart: Double, newEnd: Double)
}

/// Timeline de l'éditeur : segments de zoom (cliquables), marqueurs de
/// clics, zone rognée grisée et tête de lecture.
final class TimelineView: NSView {
    weak var delegate: TimelineViewDelegate?

    var duration: Double = 1 { didSet { needsDisplay = true } }
    var playhead: Double = 0 { didSet { needsDisplay = true } }
    var segments: [ZoomSegment] = [] {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var clickTimes: [Double] = [] { didSet { needsDisplay = true } }
    var trimStart: Double = 0 { didSet { needsDisplay = true } }
    var trimEnd: Double = 1 { didSet { needsDisplay = true } }
    var selectedSegmentID: UUID? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    private func x(for t: Double) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(t / duration) * bounds.width
    }

    private func time(for x: CGFloat) -> Double {
        guard bounds.width > 0 else { return 0 }
        return min(max(0, Double(x / bounds.width) * duration), duration)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 8

        // Fond.
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        // Zones rognées (avant trimStart, après trimEnd).
        NSColor.black.withAlphaComponent(0.45).setFill()
        let startX = x(for: trimStart)
        if startX > 0 {
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: startX, height: bounds.height)).fill()
        }
        let endX = x(for: trimEnd)
        if endX < bounds.width {
            NSBezierPath(rect: NSRect(x: endX, y: 0, width: bounds.width - endX, height: bounds.height)).fill()
        }

        // Segments de zoom.
        let barRect = { (segment: ZoomSegment) -> NSRect in
            NSRect(
                x: self.x(for: segment.start),
                y: 10,
                width: max(4, self.x(for: segment.end) - self.x(for: segment.start)),
                height: self.bounds.height - 20
            )
        }
        for segment in segments {
            let rect = barRect(segment)
            let base = NSColor.controlAccentColor
            let color = segment.enabled
                ? base.withAlphaComponent(0.75)
                : base.withAlphaComponent(0.22)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()

            if segment.id == selectedSegmentID {
                NSColor.white.setStroke()
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), xRadius: 6, yRadius: 6)
                path.lineWidth = 2
                path.stroke()
            }
        }

        // Marqueurs de clics.
        NSColor.white.withAlphaComponent(0.6).setFill()
        for t in clickTimes {
            let cx = x(for: t)
            let dot = NSRect(x: cx - 2, y: bounds.height - 7, width: 4, height: 4)
            NSBezierPath(ovalIn: dot).fill()
        }

        // Tête de lecture.
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: x(for: playhead) - 1, y: 0, width: 2, height: bounds.height)).fill()
    }

    // MARK: - Interactions

    private enum DragMode {
        case seek
        case resizeStart(UUID)
        case resizeEnd(UUID)
    }

    private var dragMode: DragMode = .seek
    private let edgeGrabWidth: CGFloat = 6

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let t = time(for: point.x)

        // Bord d'un segment → redimensionnement à la souris.
        for segment in segments {
            if abs(point.x - x(for: segment.start)) <= edgeGrabWidth {
                dragMode = .resizeStart(segment.id)
                delegate?.timeline(self, didSelectSegment: segment.id)
                return
            }
            if abs(point.x - x(for: segment.end)) <= edgeGrabWidth {
                dragMode = .resizeEnd(segment.id)
                delegate?.timeline(self, didSelectSegment: segment.id)
                return
            }
        }

        // Sinon : sélection du segment sous le clic + déplacement de la
        // tête de lecture.
        dragMode = .seek
        let hit = segments.first { t >= $0.start && t <= $0.end }
        delegate?.timeline(self, didSelectSegment: hit?.id)
        delegate?.timeline(self, didSeekTo: t)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let t = time(for: point.x)

        switch dragMode {
        case .seek:
            delegate?.timeline(self, didSeekTo: t)
        case .resizeStart(let id):
            guard let segment = segments.first(where: { $0.id == id }) else { return }
            let newStart = min(t, segment.end - 0.3)
            delegate?.timeline(self, didResizeSegment: id, newStart: max(0, newStart), newEnd: segment.end)
        case .resizeEnd(let id):
            guard let segment = segments.first(where: { $0.id == id }) else { return }
            let newEnd = max(t, segment.start + 0.3)
            delegate?.timeline(self, didResizeSegment: id, newStart: segment.start, newEnd: min(duration, newEnd))
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .seek
    }

    override func resetCursorRects() {
        // Curseur de redimensionnement sur les bords des segments.
        for segment in segments {
            for edge in [x(for: segment.start), x(for: segment.end)] {
                let rect = NSRect(x: edge - edgeGrabWidth, y: 0,
                                  width: edgeGrabWidth * 2, height: bounds.height)
                addCursorRect(rect, cursor: .resizeLeftRight)
            }
        }
    }
}
