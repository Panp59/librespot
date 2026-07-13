import AppKit

/// Petit message furtif en bas de l'écran (confirmations : copié, enregistré...).
final class Toast {
    static let shared = Toast()

    private var panel: NSPanel?
    private var hideTimer: Timer?

    func show(_ message: String, duration: TimeInterval = 2.2) {
        hideTimer?.invalidate()
        panel?.orderOut(nil)
        panel = nil

        guard let screen = NSScreen.main else { return }

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let padding: CGFloat = 16
        let size = NSSize(width: label.frame.width + padding * 2,
                          height: label.frame.height + 20)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.88).cgColor
        background.layer?.cornerRadius = size.height / 2
        label.frame.origin = NSPoint(x: padding, y: 10)
        background.addSubview(label)
        panel.contentView = background

        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 60
        ))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            if self.panel === panel { self.panel = nil }
        })
    }
}
