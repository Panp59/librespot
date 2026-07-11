import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let screenRecorder = ScreenRecorder()
    private let micRecorder = MicRecorder()
    private var mouseTracker: MouseTracker?
    private var exportPanel: ExportPanel?

    private var currentSession: RecordingSession?
    private var micEnabled = true

    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var micItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // Déclenche la demande d'autorisation Accessibilité (suivi des clics).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if screenRecorder.isRecording {
            mouseTracker?.stop()
            micRecorder.stop()
            screenRecorder.stop { _ in }
        }
    }

    // MARK: - Barre de menus

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()

        let menu = NSMenu()

        startItem = NSMenuItem(
            title: "Démarrer l'enregistrement",
            action: #selector(startRecording), keyEquivalent: "r"
        )
        menu.addItem(startItem)

        stopItem = NSMenuItem(
            title: "Arrêter et préparer l'export",
            action: #selector(stopRecording), keyEquivalent: "s"
        )
        stopItem.isHidden = true
        menu.addItem(stopItem)

        micItem = NSMenuItem(
            title: "Enregistrer le micro",
            action: #selector(toggleMic), keyEquivalent: ""
        )
        micItem.state = .on
        menu.addItem(micItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Exporter à nouveau le dernier enregistrement",
            action: #selector(exportLatest), keyEquivalent: "e"
        ))
        menu.addItem(NSMenuItem(
            title: "Ouvrir le dossier des enregistrements",
            action: #selector(openRecordingsFolder), keyEquivalent: "o"
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter Clap", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func updateStatusIcon() {
        let symbolName = screenRecorder.isRecording ? "record.circle.fill" : "video.circle"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Clap")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: - Enregistrement

    @objc private func startRecording() {
        guard !screenRecorder.isRecording else { return }
        guard let screen = NSScreen.main else { return }

        let session: RecordingSession
        do {
            session = try RecordingSession.create()
        } catch {
            showAlert(title: "Impossible de créer le dossier d'enregistrement",
                      message: error.localizedDescription)
            return
        }

        let begin = { [weak self] in
            guard let self else { return }
            self.screenRecorder.start(to: session.rawVideoURL) { error in
                if let error {
                    self.showAlert(
                        title: "Impossible de démarrer la capture",
                        message: "Vérifie l'autorisation dans Réglages Système → Confidentialité et sécurité → Enregistrement de l'écran.\n\nDétail : \(error.localizedDescription)"
                    )
                    return
                }
                if self.micEnabled {
                    do {
                        try self.micRecorder.start(to: session.micURL)
                    } catch {
                        NSLog("Clap: micro indisponible: \(error)")
                    }
                }
                let tracker = MouseTracker(screen: screen)
                tracker.start()
                self.mouseTracker = tracker
                self.currentSession = session
                self.startItem.isHidden = true
                self.stopItem.isHidden = false
                self.updateStatusIcon()
            }
        }

        if micEnabled {
            MicRecorder.requestPermission { _ in begin() }
        } else {
            begin()
        }
    }

    @objc private func stopRecording() {
        guard screenRecorder.isRecording, let session = currentSession else { return }

        let stopTime = CACurrentMediaTime()
        let tracker = mouseTracker
        tracker?.stop()
        mouseTracker = nil
        let micStart = micRecorder.startTime
        let micWasRecording = micRecorder.isRecording
        micRecorder.stop()

        screenRecorder.stop { [weak self] error in
            guard let self else { return }
            self.currentSession = nil
            self.startItem.isHidden = false
            self.stopItem.isHidden = true
            self.updateStatusIcon()

            if let error {
                self.showAlert(title: "L'enregistrement a échoué", message: error.localizedDescription)
                return
            }
            guard let videoStart = self.screenRecorder.firstFrameTime else {
                self.showAlert(
                    title: "Enregistrement vide",
                    message: "Aucune image n'a été capturée. Vérifie l'autorisation d'enregistrement de l'écran."
                )
                return
            }

            // Normalise les temps sur la première image vidéo.
            let duration = stopTime - videoStart
            let points = (tracker?.points ?? [])
                .map { MousePoint(t: $0.t - videoStart, x: $0.x, y: $0.y) }
                .filter { $0.t >= 0 }
            let clicks = (tracker?.clicks ?? [])
                .map { MouseClick(t: $0.t - videoStart, x: $0.x, y: $0.y) }
                .filter { $0.t >= 0 && $0.t <= duration }

            let data = RecordingData(
                pixelWidth: Double(self.screenRecorder.pixelSize.width),
                pixelHeight: Double(self.screenRecorder.pixelSize.height),
                duration: duration,
                hasMic: micWasRecording,
                micOffset: micWasRecording ? videoStart - (micStart ?? videoStart) : 0,
                points: points,
                clicks: clicks
            )
            do {
                try session.save(data)
            } catch {
                self.showAlert(title: "Impossible de sauvegarder la session",
                               message: error.localizedDescription)
                return
            }

            self.exportPanel = ExportPanel(session: session, data: data)
            self.exportPanel?.show()
        }
    }

    @objc private func toggleMic() {
        micEnabled.toggle()
        micItem.state = micEnabled ? .on : .off
    }

    // MARK: - Divers

    @objc private func exportLatest() {
        guard let session = RecordingSession.latest(), let data = try? session.load() else {
            showAlert(title: "Aucun enregistrement",
                      message: "Aucune session exportable dans \(RecordingSession.recordingsRoot.path).")
            return
        }
        exportPanel = ExportPanel(session: session, data: data)
        exportPanel?.show()
    }

    @objc private func openRecordingsFolder() {
        try? FileManager.default.createDirectory(
            at: RecordingSession.recordingsRoot, withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(RecordingSession.recordingsRoot)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
