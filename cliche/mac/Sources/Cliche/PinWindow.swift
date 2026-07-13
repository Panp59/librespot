import AppKit

/// Capture épinglée : une petite fenêtre flottante toujours visible, comme
/// le « Pin » de CleanShot. Glisser pour déplacer, molette pour redimensionner,
/// double-clic pour fermer.
final class PinWindowController: NSObject {
    private static var active: [PinWindowController] = []

    private let window: NSPanel
    private let imageSize: NSSize

    static func pin(image: NSImage) {
        let controller = PinWindowController(image: image)
        active.append(controller)
        controller.show()
    }

    private init(image: NSImage) {
        // L'image est en pixels ; à l'écran on vise la taille "naturelle"
        // (Retina : pixels / 2), plafonnée à la moitié de l'écran.
        imageSize = image.size
        var size = NSSize(width: image.size.width / 2, height: image.size.height / 2)
        if let screen = NSScreen.main {
            let maxW = screen.visibleFrame.width * 0.5
            let maxH = screen.visibleFrame.height * 0.5
            let scale = min(1, maxW / max(size.width, 1), maxH / max(size.height, 1))
            size = NSSize(width: size.width * scale, height: size.height * scale)
        }
        size.width = max(size.width, 120)
        size.height = max(size.height, 80)

        window = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false

        super.init()

        let view = PinImageView(image: image)
        view.onClose = { [weak self] in self?.close() }
        view.onResize = { [weak self] factor in self?.resize(by: factor) }
        view.onCopy = { [weak self] in self?.copyImage() }
        view.onActualSize = { [weak self] in self?.actualSize() }
        window.contentView = view
    }

    private func copyImage() {
        guard let view = window.contentView as? PinImageView else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([view.pinnedImage])
        Toast.shared.show("Copié dans le presse-papiers")
    }

    /// Revient à la taille naturelle (pixels Retina / 2), bornée à l'écran.
    private func actualSize() {
        let frame = window.frame
        var w = imageSize.width / 2
        if let screen = NSScreen.main {
            w = min(w, screen.visibleFrame.width * 0.95)
        }
        let h = w * imageSize.height / max(imageSize.width, 1)
        window.setFrame(
            NSRect(x: frame.minX, y: frame.maxY - h, width: w, height: h),
            display: true,
            animate: true
        )
    }

    private func show() {
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let offset = CGFloat(Self.active.count % 5) * 28
            window.setFrameOrigin(NSPoint(
                x: frame.maxX - window.frame.width - 32 - offset,
                y: frame.maxY - window.frame.height - 32 - offset
            ))
        }
        window.orderFrontRegardless()
        Toast.shared.show("Capture épinglée (double-clic pour fermer)")
    }

    private func resize(by factor: CGFloat) {
        let frame = window.frame
        var w = frame.width * factor
        w = min(max(w, 90), (NSScreen.main?.frame.width ?? 3000) * 0.95)
        let h = w * imageSize.height / max(imageSize.width, 1)
        // Redimensionne autour du coin supérieur gauche pour rester stable.
        let newFrame = NSRect(
            x: frame.minX,
            y: frame.maxY - h,
            width: w,
            height: h
        )
        window.setFrame(newFrame, display: true, animate: false)
    }

    private func close() {
        window.orderOut(nil)
        Self.active.removeAll { $0 === self }
    }
}

/// Vue de la capture épinglée : coins arrondis, liseré discret,
/// gestion molette + double-clic.
private final class PinImageView: NSView {
    private let image: NSImage
    var onClose: (() -> Void)?
    var onResize: ((CGFloat) -> Void)?
    var onCopy: (() -> Void)?
    var onActualSize: (() -> Void)?

    var pinnedImage: NSImage { image }

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = "Molette : taille, double-clic : fermer, clic droit : menu"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non implémenté") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSGraphicsContext.current?.saveGraphicsState()
        path.addClip()
        image.draw(in: bounds.insetBy(dx: 1, dy: 1))
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onClose?()
            return
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.1 else { return }
        let factor = 1 + min(max(delta * 0.004, -0.15), 0.15)
        onResize?(factor)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Copier", action: #selector(menuCopy), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        let sizeItem = NSMenuItem(title: "Taille réelle", action: #selector(menuActualSize), keyEquivalent: "")
        sizeItem.target = self
        menu.addItem(sizeItem)
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Fermer l'épingle", action: #selector(menuClose), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func menuCopy() { onCopy?() }
    @objc private func menuActualSize() { onActualSize?() }
    @objc private func menuClose() { onClose?() }
}
