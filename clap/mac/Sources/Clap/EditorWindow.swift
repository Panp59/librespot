import AppKit
import UniformTypeIdentifiers

/// Fenêtre d'édition affichée après un enregistrement : aperçu fidèle à
/// l'export, timeline avec zooms modifiables, rognage, réglages d'habillage,
/// webcam, touches clavier, puis export avec progression et annulation.
final class EditorWindow: NSObject, TimelineViewDelegate, NSWindowDelegate {
    private let session: RecordingSession
    private var data: RecordingData

    private var segments: [ZoomSegment]
    private var settings = ExportSettings()
    private var playhead: Double = 0
    private var selectedSegmentID: UUID?
    private var solidColor = NSColor(calibratedWhite: 0.12, alpha: 1)
    private var backgroundImage: CGImage?

    private var window: NSWindow?
    private var engine: PreviewEngine?
    private var renderer: Renderer?
    private var playTimer: Timer?
    private var keyMonitor: Any?
    private var backgroundImagePath: String?
    private var colorObservation: NSKeyValueObservation?

    // Aperçu.
    private let previewView = NSImageView()
    private let timelineView = TimelineView()
    private let playButton = NSButton(title: "▶︎", target: nil, action: nil)
    private let timeLabel = NSTextField(labelWithString: "0:00,0")

    // Zooms et rognage.
    private let addZoomButton = NSButton(title: "＋ Zoom ici", target: nil, action: nil)
    private let toggleZoomButton = NSButton(title: "Activer/Désactiver", target: nil, action: nil)
    private let deleteZoomButton = NSButton(title: "Supprimer", target: nil, action: nil)
    private let trimStartButton = NSButton(title: "Début ici", target: nil, action: nil)
    private let trimEndButton = NSButton(title: "Fin ici", target: nil, action: nil)
    private let trimResetButton = NSButton(title: "Réinitialiser", target: nil, action: nil)

    // Réglages.
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let backgroundPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let colorWell = NSColorWell()
    private let paddingSlider = NSSlider(value: 0.07, minValue: 0, maxValue: 0.16, target: nil, action: nil)
    private let cornerSlider = NSSlider(value: 18, minValue: 0, maxValue: 48, target: nil, action: nil)
    private let zoomSlider = NSSlider(value: 1.9, minValue: 1.0, maxValue: 3.0, target: nil, action: nil)
    private let cursorSlider = NSSlider(value: 2.0, minValue: 1.0, maxValue: 3.5, target: nil, action: nil)
    private let micCheckbox = NSButton(checkboxWithTitle: "Son du micro", target: nil, action: nil)
    private let webcamCheckbox = NSButton(checkboxWithTitle: "Webcam", target: nil, action: nil)
    private let webcamCornerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let webcamShapePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let webcamSizeSlider = NSSlider(value: 0.24, minValue: 0.12, maxValue: 0.4, target: nil, action: nil)
    private let keysCheckbox = NSButton(checkboxWithTitle: "Afficher les touches tapées", target: nil, action: nil)

    // Export.
    private let exportButton = NSButton(title: "Exporter la vidéo…", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Annuler", target: nil, action: nil)
    private let progressBar = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")

    /// Taille (pixels) du canevas d'aperçu, même ratio que la sortie.
    private var previewCanvasSize: CGSize {
        let maxWidth: CGFloat = 960
        let scale = min(1, maxWidth / settings.outputSize.width)
        return CGSize(
            width: (settings.outputSize.width * scale).rounded(),
            height: (settings.outputSize.height * scale).rounded()
        )
    }

    init(session: RecordingSession, data: RecordingData) {
        self.session = session
        self.data = data
        self.segments = data.effectiveZoomSegments
        super.init()
        settings.trimStart = data.trimStart
        settings.trimEnd = data.effectiveTrimEnd
        settings.includeMic = data.hasMic
        settings.showWebcam = data.hasWebcam
        settings.showKeystrokes = !data.keys.isEmpty
        playhead = data.trimStart
    }

    func show() {
        if window == nil {
            buildWindow()
            rebuildEngine()
            refreshTimeline()
            refreshPreview(exact: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Construction de l'interface

    private func buildWindow() {
        // Aperçu.
        previewView.imageScaling = .scaleProportionallyUpOrDown
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
        previewView.layer?.cornerRadius = 8
        previewView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewView.widthAnchor.constraint(equalToConstant: 672),
            previewView.heightAnchor.constraint(equalToConstant: 378),
        ])

        timelineView.delegate = self
        timelineView.translatesAutoresizingMaskIntoConstraints = false
        timelineView.heightAnchor.constraint(equalToConstant: 56).isActive = true

        playButton.bezelStyle = .rounded
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let transportRow = NSStackView(views: [
            playButton, timeLabel, NSView(),
            NSTextField(labelWithString: "Rognage :"),
            trimStartButton, trimEndButton, trimResetButton,
        ])
        transportRow.orientation = .horizontal
        transportRow.spacing = 8

        let zoomRow = NSStackView(views: [
            NSTextField(labelWithString: "Zooms :"),
            addZoomButton, toggleZoomButton, deleteZoomButton, NSView(),
        ])
        zoomRow.orientation = .horizontal
        zoomRow.spacing = 8

        let leftColumn = NSStackView(views: [previewView, timelineView, transportRow, zoomRow])
        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = 10
        timelineView.widthAnchor.constraint(equalTo: previewView.widthAnchor).isActive = true
        transportRow.widthAnchor.constraint(equalTo: previewView.widthAnchor).isActive = true
        zoomRow.widthAnchor.constraint(equalTo: previewView.widthAnchor).isActive = true

        // Colonne de réglages.
        for format in OutputFormat.all {
            formatPopup.addItem(withTitle: format.name)
        }
        for preset in BackgroundPreset.all {
            backgroundPopup.addItem(withTitle: preset.name)
        }
        backgroundPopup.menu?.addItem(.separator())
        backgroundPopup.addItem(withTitle: "Couleur unie")
        backgroundPopup.addItem(withTitle: "Image…")
        colorWell.color = solidColor
        colorWell.isHidden = true
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true

        for corner in WebcamCorner.allCases {
            webcamCornerPopup.addItem(withTitle: corner.name)
        }
        for shape in WebcamShape.allCases {
            webcamShapePopup.addItem(withTitle: shape.name)
        }

        micCheckbox.state = data.hasMic ? .on : .off
        micCheckbox.isEnabled = data.hasMic
        webcamCheckbox.state = data.hasWebcam ? .on : .off
        webcamCheckbox.isEnabled = data.hasWebcam
        webcamCornerPopup.isEnabled = data.hasWebcam
        webcamShapePopup.isEnabled = data.hasWebcam
        webcamSizeSlider.isEnabled = data.hasWebcam
        keysCheckbox.state = data.keys.isEmpty ? .off : .on
        keysCheckbox.isEnabled = !data.keys.isEmpty

        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }

        let settingsGrid = NSGridView(views: [
            [label("Format :"), formatPopup],
            [label("Fond :"), backgroundPopup],
            [NSGridCell.emptyContentView, colorWell],
            [label("Marge :"), paddingSlider],
            [label("Coins arrondis :"), cornerSlider],
            [label("Intensité du zoom :"), zoomSlider],
            [label("Taille du curseur :"), cursorSlider],
            [NSGridCell.emptyContentView, micCheckbox],
            [NSGridCell.emptyContentView, webcamCheckbox],
            [label("Position webcam :"), webcamCornerPopup],
            [label("Forme webcam :"), webcamShapePopup],
            [label("Taille webcam :"), webcamSizeSlider],
            [NSGridCell.emptyContentView, keysCheckbox],
        ])
        settingsGrid.rowSpacing = 9
        settingsGrid.columnSpacing = 10
        settingsGrid.column(at: 0).xPlacement = .trailing
        settingsGrid.translatesAutoresizingMaskIntoConstraints = false
        paddingSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        let rightColumn = NSStackView(views: [settingsGrid])
        rightColumn.orientation = .vertical
        rightColumn.alignment = .leading

        let mainRow = NSStackView(views: [leftColumn, rightColumn])
        mainRow.orientation = .horizontal
        mainRow.alignment = .top
        mainRow.spacing = 20

        // Barre du bas.
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.isHidden = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.widthAnchor.constraint(equalToConstant: 200).isActive = true
        cancelButton.isHidden = true
        exportButton.keyEquivalent = "\r"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail

        let bottomRow = NSStackView(views: [statusLabel, NSView(), progressBar, cancelButton, exportButton])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 10

        let root = NSStackView(views: [mainRow, bottomRow])
        root.orientation = .vertical
        root.spacing = 14
        root.alignment = .leading
        root.translatesAutoresizingMaskIntoConstraints = false
        bottomRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clap — \(session.directory.lastPathComponent)"
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        // Actions.
        let controls: [(NSControl, Selector)] = [
            (playButton, #selector(togglePlayback)),
            (addZoomButton, #selector(addZoomAtPlayhead)),
            (toggleZoomButton, #selector(toggleSelectedZoom)),
            (deleteZoomButton, #selector(deleteSelectedZoom)),
            (trimStartButton, #selector(setTrimStart)),
            (trimEndButton, #selector(setTrimEnd)),
            (trimResetButton, #selector(resetTrim)),
            (formatPopup, #selector(settingsChanged)),
            (backgroundPopup, #selector(backgroundChoiceChanged)),
            (paddingSlider, #selector(settingsChanged)),
            (cornerSlider, #selector(settingsChanged)),
            (zoomSlider, #selector(settingsChanged)),
            (cursorSlider, #selector(settingsChanged)),
            (micCheckbox, #selector(settingsChanged)),
            (webcamCheckbox, #selector(settingsChanged)),
            (webcamCornerPopup, #selector(settingsChanged)),
            (webcamShapePopup, #selector(settingsChanged)),
            (webcamSizeSlider, #selector(settingsChanged)),
            (keysCheckbox, #selector(settingsChanged)),
            (exportButton, #selector(startExport)),
            (cancelButton, #selector(cancelExport)),
        ]
        for (control, action) in controls {
            control.target = self
            control.action = action
        }

        // Le puits de couleur ne notifie pas de façon fiable par
        // target/action sur macOS 13 : on observe la couleur en KVO.
        colorObservation = colorWell.observe(\.color) { [weak self] _, _ in
            self?.settingsChanged()
        }

        restoreSettings()

        // Raccourcis clavier : espace = lecture, ←/→ = image par image
        // (avec ⇧ : par seconde).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  window.isKeyWindow, window.attachedSheet == nil
            else { return event }
            let bigStep = event.modifierFlags.contains(.shift)
            switch event.keyCode {
            case 49: // espace
                self.togglePlayback()
                return nil
            case 123: // ←
                self.step(by: bigStep ? -1.0 : -1.0 / 30.0)
                return nil
            case 124: // →
                self.step(by: bigStep ? 1.0 : 1.0 / 30.0)
                return nil
            default:
                return event
            }
        }
    }

    private func step(by delta: Double) {
        stopPlaybackIfNeeded()
        playhead = min(max(0, playhead + delta), data.duration)
        refreshPreview(exact: true)
    }

    // MARK: - Préférences mémorisées

    private static let defaultsPrefix = "Clap.editor."

    private func persistSettings() {
        let d = UserDefaults.standard
        let p = Self.defaultsPrefix
        d.set(formatPopup.indexOfSelectedItem, forKey: p + "formatIndex")
        d.set(backgroundPopup.indexOfSelectedItem, forKey: p + "backgroundIndex")
        if let rgb = colorWell.color.usingColorSpace(.deviceRGB) {
            d.set(
                [Double(rgb.redComponent), Double(rgb.greenComponent),
                 Double(rgb.blueComponent)],
                forKey: p + "solidColor"
            )
        }
        d.set(backgroundImagePath, forKey: p + "imagePath")
        d.set(paddingSlider.doubleValue, forKey: p + "padding")
        d.set(cornerSlider.doubleValue, forKey: p + "corners")
        d.set(zoomSlider.doubleValue, forKey: p + "zoom")
        d.set(cursorSlider.doubleValue, forKey: p + "cursor")
        d.set(webcamCornerPopup.indexOfSelectedItem, forKey: p + "webcamCorner")
        d.set(webcamShapePopup.indexOfSelectedItem, forKey: p + "webcamShape")
        d.set(webcamSizeSlider.doubleValue, forKey: p + "webcamSize")
    }

    private func restoreSettings() {
        let d = UserDefaults.standard
        let p = Self.defaultsPrefix
        guard d.object(forKey: p + "padding") != nil else { return } // premier lancement

        formatPopup.selectItem(at: min(max(0, d.integer(forKey: p + "formatIndex")), OutputFormat.all.count - 1))
        if let components = d.array(forKey: p + "solidColor") as? [Double], components.count == 3 {
            solidColor = NSColor(
                calibratedRed: components[0], green: components[1],
                blue: components[2], alpha: 1
            )
            colorWell.color = solidColor
        }
        if let path = d.string(forKey: p + "imagePath"),
           let image = NSImage(contentsOfFile: path)?
               .cgImage(forProposedRect: nil, context: nil, hints: nil) {
            backgroundImagePath = path
            backgroundImage = image
        }
        let presetCount = BackgroundPreset.all.count
        var backgroundIndex = d.integer(forKey: p + "backgroundIndex")
        if backgroundIndex == presetCount + 2 && backgroundImage == nil {
            backgroundIndex = 0 // l'image mémorisée n'existe plus
        }
        if backgroundIndex >= 0 && backgroundIndex < backgroundPopup.numberOfItems {
            backgroundPopup.selectItem(at: backgroundIndex)
        }
        colorWell.isHidden = backgroundIndex != presetCount + 1
        paddingSlider.doubleValue = d.double(forKey: p + "padding")
        cornerSlider.doubleValue = d.double(forKey: p + "corners")
        zoomSlider.doubleValue = d.double(forKey: p + "zoom")
        cursorSlider.doubleValue = d.double(forKey: p + "cursor")
        webcamCornerPopup.selectItem(at: min(max(0, d.integer(forKey: p + "webcamCorner")), WebcamCorner.allCases.count - 1))
        webcamShapePopup.selectItem(at: min(max(0, d.integer(forKey: p + "webcamShape")), WebcamShape.allCases.count - 1))
        webcamSizeSlider.doubleValue = d.double(forKey: p + "webcamSize")

        settingsChanged()
    }

    // MARK: - Moteur d'aperçu

    private func makeComposer() -> FrameComposer {
        FrameComposer(data: data, settings: settings, segments: segments)
    }

    private func rebuildEngine() {
        let engine = PreviewEngine(
            session: session,
            data: data,
            composer: makeComposer(),
            canvasSize: previewCanvasSize
        )
        engine.onFrame { [weak self] image in
            self?.previewView.image = image
        }
        self.engine = engine
    }

    private func refreshPreview(exact: Bool) {
        engine?.requestFrame(at: playhead, exact: exact)
        timelineView.playhead = playhead
        let total = data.duration
        timeLabel.stringValue = String(
            format: "%d:%04.1f / %d:%04.1f",
            Int(playhead) / 60, playhead.truncatingRemainder(dividingBy: 60),
            Int(total) / 60, total.truncatingRemainder(dividingBy: 60)
        )
    }

    private func refreshTimeline() {
        timelineView.duration = data.duration
        timelineView.segments = segments
        timelineView.clickTimes = data.clicks.map(\.t)
        timelineView.trimStart = settings.trimStart
        timelineView.trimEnd = settings.trimEnd
        timelineView.selectedSegmentID = selectedSegmentID
    }

    private func applySettingsAndRefresh() {
        engine?.update(composer: makeComposer())
        refreshTimeline()
        refreshPreview(exact: true)
    }

    // MARK: - Lecture

    @objc private func togglePlayback() {
        if playTimer != nil {
            stopPlayback()
            return
        }
        playButton.title = "⏸"
        if playhead >= settings.trimEnd - 0.05 {
            playhead = settings.trimStart
        }
        let step = 1.0 / 15.0
        playTimer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.playhead += step
            if self.playhead >= self.settings.trimEnd {
                self.playhead = self.settings.trimEnd
                self.stopPlayback()
            }
            self.refreshPreview(exact: false)
        }
    }

    private func stopPlayback() {
        playTimer?.invalidate()
        playTimer = nil
        playButton.title = "▶︎"
        refreshPreview(exact: true)
    }

    // MARK: - TimelineViewDelegate

    func timeline(_ view: TimelineView, didSeekTo t: Double) {
        stopPlaybackIfNeeded()
        playhead = t
        refreshPreview(exact: true)
    }

    func timeline(_ view: TimelineView, didSelectSegment id: UUID?) {
        selectedSegmentID = id
        timelineView.selectedSegmentID = id
    }

    func timeline(_ view: TimelineView, didResizeSegment id: UUID, newStart: Double, newEnd: Double) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index].start = max(0, newStart)
        segments[index].end = min(data.duration, newEnd)
        applySettingsAndRefresh()
    }

    private func stopPlaybackIfNeeded() {
        if playTimer != nil { stopPlayback() }
    }

    // MARK: - Zooms

    @objc private func addZoomAtPlayhead() {
        let segment = ZoomSegment(
            start: playhead,
            end: min(playhead + 2.0, data.duration)
        )
        segments.append(segment)
        segments.sort { $0.start < $1.start }
        selectedSegmentID = segment.id
        applySettingsAndRefresh()
    }

    @objc private func toggleSelectedZoom() {
        guard let id = selectedSegmentID,
              let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index].enabled.toggle()
        applySettingsAndRefresh()
    }

    @objc private func deleteSelectedZoom() {
        guard let id = selectedSegmentID else { return }
        segments.removeAll { $0.id == id }
        selectedSegmentID = nil
        applySettingsAndRefresh()
    }

    // MARK: - Rognage

    @objc private func setTrimStart() {
        settings.trimStart = min(playhead, settings.trimEnd - 0.5)
        applySettingsAndRefresh()
    }

    @objc private func setTrimEnd() {
        settings.trimEnd = max(playhead, settings.trimStart + 0.5)
        applySettingsAndRefresh()
    }

    @objc private func resetTrim() {
        settings.trimStart = 0
        settings.trimEnd = data.duration
        applySettingsAndRefresh()
    }

    // MARK: - Réglages

    @objc private func backgroundChoiceChanged() {
        let index = backgroundPopup.indexOfSelectedItem
        let presetCount = BackgroundPreset.all.count
        colorWell.isHidden = !(index == presetCount + 1) // après le séparateur

        if index == presetCount + 2 { // « Image… »
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url,
               let image = NSImage(contentsOf: url)?
                   .cgImage(forProposedRect: nil, context: nil, hints: nil) {
                backgroundImage = image
                backgroundImagePath = url.path
            }
        }
        settingsChanged()
    }

    @objc private func settingsChanged() {
        let formatIndex = min(max(0, formatPopup.indexOfSelectedItem), OutputFormat.all.count - 1)
        let newSize = OutputFormat.all[formatIndex].size
        let sizeChanged = newSize != settings.outputSize
        settings.outputSize = newSize

        let presetCount = BackgroundPreset.all.count
        let backgroundIndex = backgroundPopup.indexOfSelectedItem
        if backgroundIndex >= 0 && backgroundIndex < presetCount {
            settings.background = .gradient(BackgroundPreset.all[backgroundIndex])
        } else if backgroundIndex == presetCount + 1 {
            solidColor = colorWell.color
            settings.background = .solid(
                solidColor.usingColorSpace(.deviceRGB)?.cgColor ?? CGColor(gray: 0.1, alpha: 1)
            )
        } else if backgroundIndex == presetCount + 2, let backgroundImage {
            settings.background = .image(backgroundImage)
        }

        settings.paddingFraction = CGFloat(paddingSlider.doubleValue)
        settings.cornerRadius = CGFloat(cornerSlider.doubleValue)
        settings.maxZoom = CGFloat(zoomSlider.doubleValue)
        settings.cursorScale = CGFloat(cursorSlider.doubleValue)
        settings.includeMic = micCheckbox.state == .on && data.hasMic
        settings.showWebcam = webcamCheckbox.state == .on && data.hasWebcam
        settings.webcamCorner = WebcamCorner(rawValue: webcamCornerPopup.indexOfSelectedItem) ?? .bottomRight
        settings.webcamShape = WebcamShape(rawValue: webcamShapePopup.indexOfSelectedItem) ?? .circle
        settings.webcamFraction = CGFloat(webcamSizeSlider.doubleValue)
        settings.showKeystrokes = keysCheckbox.state == .on

        if sizeChanged {
            // Le ratio du canevas d'aperçu change : moteur recréé.
            rebuildEngine()
            refreshTimeline()
            refreshPreview(exact: true)
        } else {
            applySettingsAndRefresh()
        }
    }

    // MARK: - Persistance des éditions

    private func saveEdits() {
        data.zoomSegments = segments
        data.trimStart = settings.trimStart
        data.trimEnd = settings.trimEnd < data.duration ? settings.trimEnd : nil
        try? session.save(data)
    }

    func windowWillClose(_ notification: Notification) {
        stopPlaybackIfNeeded()
        saveEdits()
        persistSettings()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        renderer?.cancel()
    }

    // MARK: - Export

    @objc private func startExport() {
        guard let window else { return }
        stopPlaybackIfNeeded()
        saveEdits()
        persistSettings()

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
        cancelButton.isHidden = false
        progressBar.isHidden = false
        progressBar.doubleValue = 0
        statusLabel.stringValue = "Export en cours…"

        let renderer = Renderer(session: session, data: data, settings: settings, segments: segments)
        renderer.onProgress = { [weak self] progress in
            self?.progressBar.doubleValue = progress
            self?.statusLabel.stringValue = String(format: "Export en cours… %d %%", Int(progress * 100))
        }
        self.renderer = renderer

        renderer.export(to: outputURL) { [weak self] result in
            guard let self else { return }
            self.exportButton.isEnabled = true
            self.cancelButton.isHidden = true
            self.renderer = nil
            switch result {
            case .success(let url):
                self.progressBar.doubleValue = 1
                self.statusLabel.stringValue = "✅ Export terminé."
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .failure(let error):
                self.progressBar.isHidden = true
                let cancelled = (error as NSError).code == NSUserCancelledError
                self.statusLabel.stringValue = cancelled ? "Export annulé." : "⚠️ \(error.localizedDescription)"
            }
        }
    }

    @objc private func cancelExport() {
        renderer?.cancel()
        statusLabel.stringValue = "Annulation…"
    }
}
