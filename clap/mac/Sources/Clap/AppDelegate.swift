import AppKit
import AVFoundation
import QuartzCore
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let screenRecorder = ScreenRecorder()
    private let micRecorder = MicRecorder()
    private let webcamRecorder = WebcamRecorder()
    private let keyLogger = KeyLogger()
    private var mouseTracker: MouseTracker?
    private let countdown = CountdownOverlay()
    private var editorWindow: EditorWindow?

    private var currentSession: RecordingSession?
    private var micEnabled = true
    private var webcamEnabled = false
    private var keysEnabled = false
    private var isStarting = false

    private var elapsedTimer: Timer?
    private var recordingStartDate: Date?

    private var startItem: NSMenuItem!
    private var windowSubmenuItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var micItem: NSMenuItem!
    private var webcamItem: NSMenuItem!
    private var keysItem: NSMenuItem!
    private let windowSubmenu = NSMenu()
    private var shareableContent: SCShareableContent?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // Déclenche la demande d'autorisation Accessibilité (clics, touches).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if screenRecorder.isRecording {
            mouseTracker?.stop()
            keyLogger.stop()
            micRecorder.stop()
            webcamRecorder.stop {}
            screenRecorder.stop { _ in }
        }
    }

    // MARK: - Barre de menus

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()

        let menu = NSMenu()

        startItem = NSMenuItem(
            title: "Enregistrer l'écran",
            action: #selector(startScreenRecording), keyEquivalent: "r"
        )
        menu.addItem(startItem)

        windowSubmenuItem = NSMenuItem(title: "Enregistrer une fenêtre", action: nil, keyEquivalent: "")
        windowSubmenu.delegate = self
        windowSubmenuItem.submenu = windowSubmenu
        menu.addItem(windowSubmenuItem)

        stopItem = NSMenuItem(
            title: "Arrêter et ouvrir l'éditeur",
            action: #selector(stopRecording), keyEquivalent: "s"
        )
        stopItem.isHidden = true
        menu.addItem(stopItem)
        menu.addItem(.separator())

        micItem = NSMenuItem(title: "Micro", action: #selector(toggleMic), keyEquivalent: "")
        micItem.state = .on
        menu.addItem(micItem)
        webcamItem = NSMenuItem(title: "Webcam", action: #selector(toggleWebcam), keyEquivalent: "")
        webcamItem.state = .off
        menu.addItem(webcamItem)
        keysItem = NSMenuItem(
            title: "Enregistrer les touches tapées",
            action: #selector(toggleKeys), keyEquivalent: ""
        )
        keysItem.state = .off
        menu.addItem(keysItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Rouvrir le dernier enregistrement",
            action: #selector(openLatest), keyEquivalent: "e"
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
        let recording = screenRecorder.isRecording
        let symbolName = recording ? "record.circle.fill" : "video.circle"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Clap")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = recording ? .imageLeft : .imageOnly
        if !recording {
            statusItem.button?.title = ""
        }
    }

    private func startElapsedTimer() {
        recordingStartDate = Date()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartDate else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            self.statusItem.button?.title = String(format: " %d:%02d", elapsed / 60, elapsed % 60)
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recordingStartDate = nil
    }

    // MARK: - Sous-menu des fenêtres

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === windowSubmenu else { return }
        menu.removeAllItems()
        let loading = NSMenuItem(title: "Recherche des fenêtres…", action: nil, keyEquivalent: "")
        loading.isEnabled = false
        menu.addItem(loading)

        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.shareableContent = content
                menu.removeAllItems()
                let windows = (content?.windows ?? []).filter { window in
                    guard let app = window.owningApplication else { return false }
                    return window.isOnScreen
                        && window.frame.width >= 200 && window.frame.height >= 150
                        && app.bundleIdentifier != Bundle.main.bundleIdentifier
                        && !(window.title ?? "").isEmpty
                }
                if windows.isEmpty {
                    let empty = NSMenuItem(title: "Aucune fenêtre disponible", action: nil, keyEquivalent: "")
                    empty.isEnabled = false
                    menu.addItem(empty)
                    return
                }
                for window in windows {
                    let appName = window.owningApplication?.applicationName ?? "?"
                    let title = window.title ?? ""
                    let item = NSMenuItem(
                        title: "\(appName) — \(String(title.prefix(40)))",
                        action: #selector(self.startWindowRecording(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = window
                    menu.addItem(item)
                }
            }
        }
    }

    // MARK: - Enregistrement

    @objc private func startScreenRecording() {
        guard let screen = NSScreen.main else { return }
        beginRecording(target: .mainDisplay, area: .display(screen: screen))
    }

    @objc private func startWindowRecording(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? SCWindow else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        beginRecording(
            target: .window(window),
            area: .window(windowID: window.windowID, scale: scale)
        )
    }

    private func beginRecording(target: ScreenRecorder.Target, area: CaptureArea) {
        guard !screenRecorder.isRecording, !isStarting else { return }
        isStarting = true

        let session: RecordingSession
        do {
            session = try RecordingSession.create()
        } catch {
            isStarting = false
            showAlert(title: "Impossible de créer le dossier d'enregistrement",
                      message: error.localizedDescription)
            return
        }

        let proceed = { [weak self] in
            guard let self else { return }
            self.countdown.run(seconds: 3) {
                self.screenRecorder.start(to: session.rawVideoURL, target: target) { error in
                    self.isStarting = false
                    if let error {
                        self.showAlert(
                            title: "Impossible de démarrer la capture",
                            message: "Vérifie l'autorisation dans Réglages Système → Confidentialité et sécurité → Enregistrement de l'écran.\n\nDétail : \(error.localizedDescription)"
                        )
                        return
                    }
                    if self.micEnabled {
                        do { try self.micRecorder.start(to: session.micURL) }
                        catch { NSLog("Clap: micro indisponible: \(error)") }
                    }
                    if self.webcamEnabled {
                        do { try self.webcamRecorder.start(to: session.webcamURL) }
                        catch { NSLog("Clap: webcam indisponible: \(error)") }
                    }
                    if self.keysEnabled {
                        self.keyLogger.start()
                    }
                    let tracker = MouseTracker(area: area)
                    tracker.start()
                    self.mouseTracker = tracker
                    self.currentSession = session
                    self.startItem.isHidden = true
                    self.windowSubmenuItem.isHidden = true
                    self.stopItem.isHidden = false
                    self.updateStatusIcon()
                    self.startElapsedTimer()
                }
            }
        }

        // Demande les autorisations micro/webcam avant le compte à rebours.
        if micEnabled {
            MicRecorder.requestPermission { [weak self] _ in
                if self?.webcamEnabled == true {
                    WebcamRecorder.requestPermission { _ in proceed() }
                } else {
                    proceed()
                }
            }
        } else if webcamEnabled {
            WebcamRecorder.requestPermission { _ in proceed() }
        } else {
            proceed()
        }
    }

    @objc private func stopRecording() {
        guard screenRecorder.isRecording, let session = currentSession else { return }

        let stopTime = CACurrentMediaTime()
        let tracker = mouseTracker
        tracker?.stop()
        mouseTracker = nil
        keyLogger.stop()
        let keyEvents = keyLogger.events

        let micStart = micRecorder.startTime
        let micWasRecording = micRecorder.isRecording
        micRecorder.stop()

        let webcamWasRecording = webcamRecorder.isRecording
        let webcamStart = webcamRecorder.firstFrameTime

        stopElapsedTimer()

        webcamRecorder.stop { [weak self] in
            guard let self else { return }
            self.screenRecorder.stop { error in
                self.currentSession = nil
                self.startItem.isHidden = false
                self.windowSubmenuItem.isHidden = false
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

                // Normalise tous les temps sur la première image vidéo.
                let duration = stopTime - videoStart
                var data = RecordingData(
                    pixelWidth: Double(self.screenRecorder.pixelSize.width),
                    pixelHeight: Double(self.screenRecorder.pixelSize.height),
                    duration: duration
                )
                data.hasMic = micWasRecording
                data.micOffset = micWasRecording ? videoStart - (micStart ?? videoStart) : 0
                data.hasWebcam = webcamWasRecording && webcamStart != nil
                data.webcamOffset = data.hasWebcam ? videoStart - (webcamStart ?? videoStart) : 0
                data.points = (tracker?.points ?? [])
                    .map { MousePoint(t: $0.t - videoStart, x: $0.x, y: $0.y) }
                    .filter { $0.t >= 0 }
                data.clicks = (tracker?.clicks ?? [])
                    .map { MouseClick(t: $0.t - videoStart, x: $0.x, y: $0.y) }
                    .filter { $0.t >= 0 && $0.t <= duration }
                data.keys = keyEvents
                    .map { KeyEvent(t: $0.t - videoStart, text: $0.text, isShortcut: $0.isShortcut) }
                    .filter { $0.t >= 0 && $0.t <= duration }

                do {
                    try session.save(data)
                } catch {
                    self.showAlert(title: "Impossible de sauvegarder la session",
                                   message: error.localizedDescription)
                    return
                }

                self.editorWindow = EditorWindow(session: session, data: data)
                self.editorWindow?.show()
            }
        }
    }

    // MARK: - Options

    @objc private func toggleMic() {
        micEnabled.toggle()
        micItem.state = micEnabled ? .on : .off
    }

    @objc private func toggleWebcam() {
        webcamEnabled.toggle()
        webcamItem.state = webcamEnabled ? .on : .off
    }

    @objc private func toggleKeys() {
        keysEnabled.toggle()
        keysItem.state = keysEnabled ? .on : .off
    }

    // MARK: - Divers

    @objc private func openLatest() {
        guard let session = RecordingSession.latest(), let data = try? session.load() else {
            showAlert(title: "Aucun enregistrement",
                      message: "Aucune session exploitable dans \(RecordingSession.recordingsRoot.path).")
            return
        }
        editorWindow = EditorWindow(session: session, data: data)
        editorWindow?.show()
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
