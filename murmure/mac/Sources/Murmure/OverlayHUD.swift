import AppKit

/// Petit panneau flottant en bas de l'écran (état : enregistrement,
/// transcription…), qui ne vole jamais le focus.
final class OverlayHUD {
    private let panel: NSPanel
    private let label: NSTextField

    init() {
        let size = NSSize(width: 280, height: 44)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        label = NSTextField(labelWithString: "")
        label.frame = container.bounds.insetBy(dx: 16, dy: 12)
        label.autoresizingMask = [.width, .height]
        label.alignment = .center
        label.font = .systemFont(ofSize: 14, weight: .medium)
        container.addSubview(label)

        panel.contentView = container
    }

    func show(_ text: String) {
        label.stringValue = text
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 80))
    }
}
