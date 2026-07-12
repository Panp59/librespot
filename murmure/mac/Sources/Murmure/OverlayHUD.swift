import AppKit
import QuartzCore

/// Capsule flottante en bas de l'écran (état : écoute, transcription…),
/// avec un point d'état qui pulse pendant l'enregistrement. Ne vole
/// jamais le focus.
final class OverlayHUD {
    enum Style {
        case info, recording, working, error
    }

    private let panel: NSPanel
    private let container: NSVisualEffectView
    private let label: NSTextField
    private let dot = NSView()
    private let height: CGFloat = 44

    init() {
        let size = NSSize(width: 320, height: height)
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

        container = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = height / 2
        container.layer?.masksToBounds = true

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        container.addSubview(dot)

        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        container.addSubview(label)

        panel.contentView = container
    }

    func show(_ text: String, style: Style = .info) {
        label.stringValue = text
        label.sizeToFit()

        let dotColor: NSColor?
        switch style {
        case .recording: dotColor = .systemRed
        case .working: dotColor = .controlAccentColor
        case .error: dotColor = .systemOrange
        case .info: dotColor = nil
        }
        dot.isHidden = dotColor == nil
        dot.layer?.backgroundColor = dotColor?.cgColor
        dot.layer?.removeAnimation(forKey: "pulse")
        if style == .recording || style == .working {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.25
            pulse.duration = style == .recording ? 0.55 : 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            dot.layer?.add(pulse, forKey: "pulse")
        }

        // Capsule ajustée à la largeur du texte.
        let textLeft: CGFloat = dotColor == nil ? 20 : 36
        let width = textLeft + label.frame.width + 20
        panel.setContentSize(NSSize(width: width, height: height))
        container.frame = NSRect(x: 0, y: 0, width: width, height: height)
        dot.frame = NSRect(x: 18, y: (height - 10) / 2, width: 10, height: 10)
        label.frame = NSRect(
            x: textLeft,
            y: (height - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )

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
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 64))
    }
}
