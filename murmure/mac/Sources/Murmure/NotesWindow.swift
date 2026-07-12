import AppKit

/// Petite fenêtre flottante de prise de notes pendant une réunion.
/// À l'arrêt, les notes servent de fil conducteur au compte-rendu
/// (façon Granola) : le LLM les développe à l'aide de la transcription.
final class NotesWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var textView: NSTextView?

    var text: String {
        textView?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func show() {
        if window == nil {
            build()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func reset() {
        textView?.string = ""
    }

    func close() {
        window?.orderOut(nil)
    }

    private func build() {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 10)
        self.textView = textView

        let hint = NSTextField(labelWithString: "Quelques mots-clés suffisent, ils guideront le compte-rendu.")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(scrollView)
        content.addSubview(hint)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -6),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notes de réunion"
        window.contentView = content
        window.isReleasedWhenClosed = false
        // Reste visible au-dessus de Teams/du plein écran, sur tous les bureaux.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self

        // Position : coin supérieur droit de l'écran principal.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: frame.maxX - window.frame.width - 24,
                y: frame.maxY - window.frame.height - 24
            ))
        }
        self.window = window
    }
}
