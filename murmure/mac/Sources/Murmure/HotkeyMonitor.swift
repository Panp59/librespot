import AppKit

/// Surveille la touche ⌥ droite (push-to-talk) partout dans le système.
/// Nécessite l'autorisation Accessibilité.
final class HotkeyMonitor {
    /// Code de la touche Option droite.
    static let rightOptionKeyCode: UInt16 = 61

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDown = false

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == Self.rightOptionKeyCode else { return }
        // .option est vrai si N'IMPORTE QUELLE touche Option est enfoncée :
        // on teste le bit spécifique de l'Option droite (NX_DEVICERALTKEYMASK)
        // pour ne pas rester bloqué si l'Option gauche est aussi enfoncée.
        let pressed = event.modifierFlags.rawValue & 0x40 != 0
        if pressed && !isDown {
            isDown = true
            onPress?()
        } else if !pressed && isDown {
            isDown = false
            onRelease?()
        }
    }
}
