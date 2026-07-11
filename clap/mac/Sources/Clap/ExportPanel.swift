import AppKit
import UniformTypeIdentifiers

/// Fenêtre de réglages affichée après un enregistrement (ou via « Exporter
/// à nouveau ») : format, fond, marge, zoom… puis export avec progression.
final class ExportPanel: NSObject {
    private let session: RecordingSession
    private let data: RecordingData
    private var window: NSWindow?
    private var renderer: Renderer?

    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let backgroundPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let paddingSlider = NSSlider(value: 0.07, minValue: 0, maxValue: 0.16, target: nil, action: nil)
    private let cornerSlider = NSSlider(value: 18, minValue: 0, maxValue: 48, target: nil, action: nil)
    private let zoomSlider = NSSlider(value: 1.9, minValue: 1.0, maxValue: 3.0, target: nil, action: nil)
    private let cursorSlider = NSSlider(value: 2.0, minValue: 1.0, maxValue: 3.5, target: nil, action: nil)
    private let micCheckbox = NSButton(checkboxWithTitle: "Inclure le son du micro", target: nil, action: nil)
    private let exportButton = NSButton(title: "Exporter la vidéo…", target: nil, action: nil)
    private let progressBar = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")

    init(session: RecordingSession, data: RecordingData) {
        self.session = session
        self.data = data
        super.init()
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildWindow() {
        for format in OutputFormat.all {
            formatPopup.addItem(withTitle: format.name)
        }
        for preset in BackgroundPreset.all {
            backgroundPopup.addItem(withTitle: preset.name)
        }
        micCheckbox.state = .on
        micCheckbox.isEnabled = data.hasMic
        if !data.hasMic {
            micCheckbox.state = .off
            micCheckbox.title = "Inclure le son du micro (pas de piste enregistrée)"
        }

        exportButton.target = self
        exportButton.action = #selector(startExport)
        exportButton.keyEquivalent = "\r"

        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.isHidden = true

        let minutes = Int(data.duration) / 60
        let seconds = Int(data.duration) % 60
        statusLabel.stringValue = String(
            format: "Enregistrement de %d:%02d — %d clic(s) détecté(s).",
            minutes, seconds, data.clicks.count
        )
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)

        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }

        let grid = NSGridView(views: [
            [label("Format :"), formatPopup],
            [label("Fond :"), backgroundPopup],
            [label("Marge :"), paddingSlider],
            [label("Coins arrondis :"), cornerSlider],
            [label("Zoom sur les clics :"), zoomSlider],
            [label("Taille du curseur :"), cursorSlider],
            [NSGridCell.emptyContentView, micCheckbox],
            [NSGridCell.emptyContentView, exportButton],
            [NSGridCell.emptyContentView, progressBar],
            [NSGridCell.emptyContentView, statusLabel],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            paddingSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clap — Exporter l'enregistrement"
        window.contentView = content
        window.isReleasedWhenClosed = false
        self.window = window
    }

    private func currentSettings() -> ExportSettings {
        var settings = ExportSettings()
        let formatIndex = max(0, formatPopup.indexOfSelectedItem)
        settings.outputSize = OutputFormat.all[min(formatIndex, OutputFormat.all.count - 1)].size
        let backgroundIndex = max(0, backgroundPopup.indexOfSelectedItem)
        settings.background = BackgroundPreset.all[min(backgroundIndex, BackgroundPreset.all.count - 1)]
        settings.paddingFraction = CGFloat(paddingSlider.doubleValue)
        settings.cornerRadius = CGFloat(cornerSlider.doubleValue)
        settings.maxZoom = CGFloat(zoomSlider.doubleValue)
        settings.cursorScale = CGFloat(cursorSlider.doubleValue)
        settings.includeMic = micCheckbox.state == .on && data.hasMic
        return settings
    }

    @objc private func startExport() {
        guard let window else { return }

        let savePanel = NSSavePanel()
        savePanel.title = "Exporter la vidéo"
        savePanel.nameFieldStringValue = session.directory.lastPathComponent + ".mp4"
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.directoryURL = FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clap", isDirectory: true)

        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let outputURL = savePanel.url else { return }
            self.runExport(to: outputURL)
        }
    }

    private func runExport(to outputURL: URL) {
        exportButton.isEnabled = false
        progressBar.isHidden = false
        progressBar.doubleValue = 0
        statusLabel.stringValue = "Export en cours…"

        let renderer = Renderer(session: session, data: data, settings: currentSettings())
        renderer.onProgress = { [weak self] progress in
            self?.progressBar.doubleValue = progress
            self?.statusLabel.stringValue = String(format: "Export en cours… %d %%", Int(progress * 100))
        }
        self.renderer = renderer

        renderer.export(to: outputURL) { [weak self] result in
            guard let self else { return }
            self.exportButton.isEnabled = true
            self.renderer = nil
            switch result {
            case .success(let url):
                self.progressBar.doubleValue = 1
                self.statusLabel.stringValue = "✅ Export terminé."
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .failure(let error):
                self.progressBar.isHidden = true
                self.statusLabel.stringValue = "⚠️ \(error.localizedDescription)"
            }
        }
    }
}
