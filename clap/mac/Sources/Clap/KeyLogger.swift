import AppKit
import QuartzCore

/// Enregistre les touches tapées pendant la capture pour pouvoir les
/// incruster dans la vidéo (option désactivée par défaut). Les événements
/// sont stockés déjà mis en forme (« ⌘⇧P », « a »…) dans session.json.
/// Nécessite l'autorisation Accessibilité.
final class KeyLogger {
    private var monitors: [Any] = []
    private(set) var events: [KeyEvent] = []

    func start() {
        events = []
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.record(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.record(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let modifiers = Self.modifierSymbols(event.modifierFlags)
        let key = Self.keyName(for: event)
        guard !key.isEmpty else { return }
        let isShortcut = !modifiers.isEmpty
        events.append(KeyEvent(
            t: CACurrentMediaTime(),
            text: isShortcut ? modifiers + key.uppercased() : key,
            isShortcut: isShortcut
        ))
    }

    private static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols
    }

    private static func keyName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36, 76: return "⏎"
        case 48: return "⇥"
        case 49: return "␣"
        case 51: return "⌫"
        case 53: return "⎋"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            return event.charactersIgnoringModifiers ?? ""
        }
    }
}
