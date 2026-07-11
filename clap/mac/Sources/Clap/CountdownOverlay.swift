import AppKit

/// Compte à rebours 3-2-1 affiché au centre de l'écran avant de démarrer
/// l'enregistrement, sans voler le focus.
final class CountdownOverlay {
    private let panel: NSPanel
    private let label: NSTextField
    private var timer: Timer?

    init() {
        let size = NSSize(width: 220, height: 220)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = size.width / 2
        container.layer?.masksToBounds = true

        label = NSTextField(labelWithString: "3")
        label.font = .systemFont(ofSize: 110, weight: .bold)
        label.alignment = .center
        label.frame = container.bounds
        label.autoresizingMask = [.width, .height]
        container.addSubview(label)
        panel.contentView = container
    }

    /// Affiche 3, 2, 1 puis appelle `completion`.
    func run(seconds: Int = 3, completion: @escaping () -> Void) {
        var remaining = seconds
        label.stringValue = "\(remaining)"
        position()
        panel.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self.timer = nil
                self.panel.orderOut(nil)
                completion()
            } else {
                self.label.stringValue = "\(remaining)"
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        ))
    }
}
