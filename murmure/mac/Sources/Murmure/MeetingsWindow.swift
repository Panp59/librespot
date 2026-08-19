import AppKit

/// Fenêtre de gestion des réunions enregistrées : liste, état de la
/// transcription, et actions (ouvrir, retranscrire, révéler, supprimer).
/// Indispensable quand une transcription n'a pas pu se faire (Mac en veille,
/// écran fermé) : l'audio est conservé, on relance quand on veut.
final class MeetingsWindowController: NSObject, NSWindowDelegate,
                                      NSTableViewDataSource, NSTableViewDelegate {
    private let recordingsDir: URL
    private let backend: BackendClient
    /// Lance une retranscription ; le contrôleur parent gère le HUD et les
    /// alertes, puis rappelle `onFinished` pour rafraîchir la liste.
    private let reprocess: (MeetingRecording, String, @escaping (Bool) -> Void) -> Void

    private var window: NSWindow?
    private var recordings: [MeetingRecording] = []
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var busyRow: Int?

    init(
        recordingsDir: URL,
        backend: BackendClient,
        reprocess: @escaping (MeetingRecording, String, @escaping (Bool) -> Void) -> Void
    ) {
        self.recordingsDir = recordingsDir
        self.backend = backend
        self.reprocess = reprocess
        super.init()
    }

    func show() {
        if window == nil { buildWindow() }
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Construction

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Réunions enregistrées"
        window.minSize = NSSize(width: 680, height: 320)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        let columns: [(String, String, CGFloat)] = [
            ("date", "Date", 150),
            ("type", "Type", 90),
            ("taille", "Audio", 80),
            ("etat", "Transcription", 130),
            ("actions", "", 300),
        ]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = 60
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 30
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnSelection = false

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "Rafraîchir", target: self, action: #selector(refreshClicked))
        let folderButton = NSButton(
            title: "Ouvrir le dossier", target: self, action: #selector(openFolderClicked)
        )
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [statusLabel, spacer, folderButton, refreshButton])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(scroll)
        content.addSubview(bar)
        window.contentView = content
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bar.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Données

    func reload() {
        recordings = MeetingRecording.all(in: recordingsDir)
        tableView.reloadData()
        let pending = recordings.filter { !$0.isTranscribed }.count
        if recordings.isEmpty {
            statusLabel.stringValue = "Aucun enregistrement."
        } else if pending > 0 {
            statusLabel.stringValue = "\(recordings.count) enregistrement(s), "
                + "\(pending) sans transcription."
        } else {
            statusLabel.stringValue = "\(recordings.count) enregistrement(s), tous transcrits."
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { recordings.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < recordings.count, let columnID = tableColumn?.identifier.rawValue else {
            return nil
        }
        let recording = recordings[row]

        if columnID == "actions" {
            return actionsView(for: row, recording: recording)
        }

        let text: String
        switch columnID {
        case "date":
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.dateFormat = "EEE d MMM, HH:mm"
            text = formatter.string(from: recording.date).capitalized
        case "type":
            text = recording.mode == "remote" ? "Teams/visio" : "Présentiel"
        case "taille":
            text = ByteCountFormatter.string(
                fromByteCount: recording.sizeBytes, countStyle: .file
            )
        case "etat":
            if busyRow == row {
                text = "En cours…"
            } else {
                text = recording.isTranscribed ? "Transcrite" : "À faire"
            }
        default:
            text = ""
        }

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        if columnID == "etat", busyRow != row, !recording.isTranscribed {
            label.textColor = .systemOrange
        }
        return label
    }

    private func actionsView(for row: Int, recording: MeetingRecording) -> NSView {
        var buttons: [NSView] = []

        if recording.documentToOpen != nil {
            buttons.append(makeButton("Ouvrir", row: row, action: #selector(openClicked(_:))))
        }
        let redoTitle = recording.isTranscribed ? "Refaire" : "Transcrire"
        let redo = makeButton(redoTitle, row: row, action: #selector(reprocessClicked(_:)))
        redo.isEnabled = busyRow == nil
        if !recording.isTranscribed {
            redo.keyEquivalent = ""
            redo.bezelColor = .controlAccentColor
        }
        buttons.append(redo)
        buttons.append(makeButton("Finder", row: row, action: #selector(revealClicked(_:))))
        buttons.append(makeButton("Supprimer", row: row, action: #selector(deleteClicked(_:))))

        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        return stack
    }

    private func makeButton(_ title: String, row: Int, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.tag = row
        return button
    }

    // MARK: - Actions

    @objc private func refreshClicked() { reload() }

    @objc private func openFolderClicked() {
        try? FileManager.default.createDirectory(
            at: recordingsDir, withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(recordingsDir)
    }

    @objc private func openClicked(_ sender: NSButton) {
        guard let recording = recording(for: sender),
              let document = recording.documentToOpen else { return }
        NSWorkspace.shared.open(document)
    }

    @objc private func revealClicked(_ sender: NSButton) {
        guard let recording = recording(for: sender) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([recording.directory])
    }

    @objc private func reprocessClicked(_ sender: NSButton) {
        guard busyRow == nil, let recording = recording(for: sender) else { return }
        guard let title = askTitle(default: defaultTitle(for: recording)) else { return }

        busyRow = sender.tag
        tableView.reloadData()
        reprocess(recording, title) { [weak self] _ in
            guard let self else { return }
            self.busyRow = nil
            self.reload()
        }
    }

    @objc private func deleteClicked(_ sender: NSButton) {
        guard let recording = recording(for: sender) else { return }
        let alert = NSAlert()
        alert.messageText = "Supprimer cet enregistrement ?"
        alert.informativeText = "L'audio sera placé dans la corbeille. "
            + "La transcription déjà produite, elle, est conservée."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Supprimer")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.trashItem(at: recording.directory, resultingItemURL: nil)
        reload()
    }

    private func recording(for sender: NSButton) -> MeetingRecording? {
        guard sender.tag >= 0, sender.tag < recordings.count else { return nil }
        return recordings[sender.tag]
    }

    private func defaultTitle(for recording: MeetingRecording) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM HH:mm"
        return "Réunion du \(formatter.string(from: recording.date))"
    }

    private func askTitle(default defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Titre de la réunion"
        alert.informativeText = "Ce titre sera utilisé pour nommer le compte-rendu."
        alert.addButton(withTitle: "Transcrire")
        alert.addButton(withTitle: "Annuler")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? defaultValue : title
    }
}
