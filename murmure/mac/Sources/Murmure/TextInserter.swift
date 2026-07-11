import AppKit

/// Insère du texte au curseur de l'application active, via le presse-papiers
/// et un ⌘V synthétique. Nécessite l'autorisation Accessibilité.
enum TextInserter {
    static func insertAtCursor(_ text: String) {
        let pasteboard = NSPasteboard.general
        let savedString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9 // touche V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Restaure le presse-papiers une fois le collage effectué.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let savedString {
                pasteboard.clearContents()
                pasteboard.setString(savedString, forType: .string)
            }
        }
    }
}
