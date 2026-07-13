import AppKit

/// La carte d'actions rapides qui apparaît en bas à droite après chaque
/// capture, comme le « quick access overlay » de CleanShot : aperçu +
/// Annoter / Copier / Texte / Épingler / Finder.
final class QuickActionsPanel: NSObject {
    private static var current: QuickActionsPanel?

    private let fileURL: URL
    private let image: NSImage
    private var panel: NSPanel?
    private var dismissTimer: Timer?

    static func show(fileURL: URL, image: NSImage) {
        current?.close(animated: false)
        let instance = QuickActionsPanel(fileURL: fileURL, image: image)
        current = instance
        instance.present()
    }

    private init(fileURL: URL, image: NSImage) {
        self.fileURL = fileURL
        self.image = image
        super.init()
    }

    private func present() {
        guard let screen = NSScreen.main else { return }

        let width: CGFloat = 300
        let thumbHeight: CGFloat = 150
        let barHeight: CGFloat = 44
        let size = NSSize(width: width, height: thumbHeight + barHeight)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = TrackingView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 0.96).cgColor
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        root.onHover = { [weak self] hovering in
            if hovering {
                self?.dismissTimer?.invalidate()
            } else {
                self?.armDismissTimer(delay: 4)
            }
        }

        let thumb = NSImageView(frame: NSRect(x: 8, y: barHeight, width: width - 16, height: thumbHeight - 8))
        thumb.image = image
        thumb.imageScaling = .scaleProportionallyDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 8
        thumb.layer?.masksToBounds = true
        root.addSubview(thumb)

        let actions: [(String, Selector)] = [
            ("Annoter", #selector(annotate)),
            ("Copier", #selector(copyImage)),
            ("Texte", #selector(ocr)),
            ("Épingler", #selector(pin)),
            ("Finder", #selector(reveal)),
        ]
        let buttons: [NSView] = actions.map { title, action in
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11)
            return button
        }
        let closeButton = NSButton(title: "✕", target: self, action: #selector(closeClicked))
        closeButton.bezelStyle = .inline
        closeButton.controlSize = .small
        closeButton.font = .systemFont(ofSize: 11)

        let bar = NSStackView(views: buttons + [closeButton])
        bar.orientation = .horizontal
        bar.spacing = 4
        bar.frame = NSRect(x: 8, y: 6, width: width - 16, height: barHeight - 12)
        bar.autoresizingMask = [.width]
        root.addSubview(bar)

        panel.contentView = root

        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - size.width - 24,
            y: frame.minY + 24
        ))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        armDismissTimer(delay: 10)
    }

    private func armDismissTimer(delay: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.close(animated: true)
        }
    }

    private func close(animated: Bool) {
        dismissTimer?.invalidate()
        guard let panel else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        } else {
            panel.orderOut(nil)
        }
        self.panel = nil
        if Self.current === self { Self.current = nil }
    }

    // MARK: actions

    @objc private func annotate() {
        close(animated: false)
        AnnotatorWindowController.open(fileURL: fileURL)
    }

    @objc private func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        Toast.shared.show("Copié dans le presse-papiers")
        close(animated: true)
    }

    @objc private func ocr() {
        close(animated: true)
        OCRService.extractAndCopy(from: image)
    }

    @objc private func pin() {
        close(animated: false)
        PinWindowController.pin(image: ImageUtils.normalized(image))
    }

    @objc private func reveal() {
        close(animated: true)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    @objc private func closeClicked() {
        close(animated: true)
    }
}

/// Vue qui signale l'entrée et la sortie de la souris (pause du minuteur).
private final class TrackingView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
