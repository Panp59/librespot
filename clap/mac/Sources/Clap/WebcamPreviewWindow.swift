import AppKit
import AVFoundation

/// Aperçu en direct de la webcam pendant l'enregistrement, pour cadrer sa
/// tête avant/pendant la prise. Fenêtre carrée (le crop de la vignette
/// finale est centré, comme ici), déplaçable, toujours au premier plan,
/// exclue de la capture d'écran... impossible (elle apparaîtrait) : elle
/// est donc discrète et se place par défaut hors du chemin, en bas à droite.
final class WebcamPreviewWindow: NSObject {
    private var panel: NSPanel?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func show(session: AVCaptureSession) {
        if panel == nil { build() }
        previewLayer?.session = session
        panel?.orderFrontRegardless()
    }

    func hide() {
        previewLayer?.session = nil
        panel?.orderOut(nil)
    }

    private func build() {
        let side: CGFloat = 200
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        content.wantsLayer = true
        content.layer?.cornerRadius = 16
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = CGColor(gray: 0.1, alpha: 1)

        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        layer.frame = content.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        content.layer?.addSublayer(layer)
        previewLayer = layer

        panel.contentView = content

        // Position par défaut : bas droite (la vignette exportée est en bas
        // gauche par défaut, l'aperçu ne la recouvre pas dans la capture).
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - side - 24, y: frame.minY + 24))
        }
        self.panel = panel
    }
}
