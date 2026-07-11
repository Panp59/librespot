import AppKit
import AVFoundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyMonitor()
    private let dictationMic = MicRecorder()
    private let meetingMic = MicRecorder()
    private let systemAudio = SystemAudioRecorder()
    private let backend = BackendClient()
    private let hud = OverlayHUD()

    private var healthTimer: Timer?
    private var backendHealthy = false
    private var backendProcess: Process?

    private var meetingMode: String? // "in_person" | "remote", nil = pas de réunion
    private var meetingDir: URL?

    // Annulation de dictée (touche Échap pendant l'enregistrement).
    private var escapeMonitors: [Any] = []
    private var dictationCancelled = false

    // Préférences.
    private var soundsEnabled = UserDefaults.standard.object(forKey: "SoundsEnabled") as? Bool ?? true
    private var autoLanguage = UserDefaults.standard.bool(forKey: "AutoLanguage")

    // Éléments de menu mis à jour dynamiquement.
    private var backendStatusItem: NSMenuItem!
    private var startInPersonItem: NSMenuItem!
    private var startRemoteItem: NSMenuItem!
    private var stopMeetingItem: NSMenuItem!
    private var soundsItem: NSMenuItem!
    private var autoLanguageItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private var dictationFileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("murmure-dictation.wav")
    }

    private var recordingsDir: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmure/Enregistrements", isDirectory: true)
    }

    // MARK: - Cycle de vie

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        requestPermissions()
        setupHotkey()

        healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkBackendHealth()
        }
        checkBackendHealth()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.stop()
        backendProcess?.terminate()
    }

    // MARK: - Barre de menus

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()

        let menu = NSMenu()

        backendStatusItem = NSMenuItem(title: "Backend : vérification…", action: nil, keyEquivalent: "")
        backendStatusItem.isEnabled = false
        menu.addItem(backendStatusItem)
        menu.addItem(NSMenuItem(
            title: "Démarrer le backend", action: #selector(startBackend), keyEquivalent: "b"
        ))
        menu.addItem(.separator())

        let hint = NSMenuItem(title: "Dictée : maintenir ⌥ droite (Échap pour annuler)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        soundsItem = NSMenuItem(title: "Sons de dictée", action: #selector(toggleSounds), keyEquivalent: "")
        soundsItem.state = soundsEnabled ? .on : .off
        menu.addItem(soundsItem)

        autoLanguageItem = NSMenuItem(
            title: "Détection automatique de la langue",
            action: #selector(toggleAutoLanguage), keyEquivalent: ""
        )
        autoLanguageItem.state = autoLanguage ? .on : .off
        menu.addItem(autoLanguageItem)
        menu.addItem(.separator())

        startInPersonItem = NSMenuItem(
            title: "Réunion en présentiel : démarrer",
            action: #selector(startInPersonMeeting), keyEquivalent: "r"
        )
        menu.addItem(startInPersonItem)
        startRemoteItem = NSMenuItem(
            title: "Réunion Teams/visio : démarrer",
            action: #selector(startRemoteMeeting), keyEquivalent: "t"
        )
        menu.addItem(startRemoteItem)
        stopMeetingItem = NSMenuItem(
            title: "Arrêter la réunion et transcrire",
            action: #selector(stopMeeting), keyEquivalent: "s"
        )
        stopMeetingItem.isHidden = true
        menu.addItem(stopMeetingItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Ouvrir le dossier des transcriptions",
            action: #selector(openOutputFolder), keyEquivalent: "o"
        ))
        menu.addItem(.separator())

        loginItem = NSMenuItem(
            title: "Lancer Murmure à l'ouverture de session",
            action: #selector(toggleLaunchAtLogin), keyEquivalent: ""
        )
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quitter Murmure", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func updateStatusIcon() {
        let symbolName: String
        if meetingMode != nil {
            symbolName = "record.circle.fill"
        } else if backendHealthy {
            symbolName = "mic.fill"
        } else {
            symbolName = "mic.slash"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Murmure")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: - Autorisations

    private func requestPermissions() {
        // Accessibilité (raccourci global + insertion du texte).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Micro.
        MicRecorder.requestPermission { granted in
            if !granted {
                self.showAlert(
                    title: "Micro non autorisé",
                    message: "Autorise Murmure à utiliser le micro dans Réglages Système → Confidentialité et sécurité → Microphone."
                )
            }
        }
    }

    // MARK: - Dictée (push-to-talk)

    private func setupHotkey() {
        hotkey.onPress = { [weak self] in self?.dictationKeyDown() }
        hotkey.onRelease = { [weak self] in self?.dictationKeyUp() }
        hotkey.start()
    }

    private func dictationKeyDown() {
        guard backendHealthy else {
            hud.show("⚠️ Backend hors ligne — menu Murmure → Démarrer le backend")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.hud.hide() }
            return
        }
        guard !dictationMic.isRecording else { return }
        do {
            try dictationMic.start(to: dictationFileURL)
            dictationCancelled = false
            installEscapeMonitors()
            playSound("Tink")
            hud.show("🎙️ Je t'écoute… (Échap pour annuler)")
        } catch {
            hud.show("⚠️ Micro indisponible")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.hud.hide() }
        }
    }

    private func dictationKeyUp() {
        removeEscapeMonitors()
        guard !dictationCancelled else { return }
        guard let (url, duration) = dictationMic.stop() else { return }
        // Appui trop bref : probablement involontaire.
        guard duration > 0.35 else {
            hud.hide()
            return
        }
        hud.show("⏳ Transcription…")
        backend.dictate(audioURL: url, language: autoLanguage ? "auto" : nil) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text) where !text.isEmpty:
                self.hud.hide()
                self.playSound("Pop")
                TextInserter.insertAtCursor(text)
            case .success:
                self.hud.show("🤔 Rien entendu")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.hud.hide() }
            case .failure(let error):
                self.hud.show("⚠️ Erreur de transcription")
                NSLog("Murmure: dictée échouée: \(error)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.hud.hide() }
            }
        }
    }

    /// Échap pendant l'enregistrement : on jette la dictée en cours.
    private func installEscapeMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            if event.keyCode == 53 { self?.cancelDictation() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            escapeMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handler(event)
            return event.keyCode == 53 ? nil : event
        }) {
            escapeMonitors.append(local)
        }
    }

    private func removeEscapeMonitors() {
        for monitor in escapeMonitors {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitors = []
    }

    private func cancelDictation() {
        guard dictationMic.isRecording else { return }
        dictationCancelled = true
        removeEscapeMonitors()
        _ = dictationMic.stop()
        playSound("Bottle")
        hud.show("Dictée annulée")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.hud.hide() }
    }

    private func playSound(_ name: String) {
        guard soundsEnabled else { return }
        NSSound(named: name)?.play()
    }

    // MARK: - Réunions

    @objc private func startInPersonMeeting() {
        startMeeting(mode: "in_person")
    }

    @objc private func startRemoteMeeting() {
        startMeeting(mode: "remote")
    }

    private func startMeeting(mode: String) {
        guard meetingMode == nil else { return }
        guard backendHealthy else {
            showAlert(
                title: "Backend hors ligne",
                message: "Démarre le backend (menu Murmure → Démarrer le backend) avant de lancer une réunion."
            )
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let dir = recordingsDir.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try meetingMic.start(to: dir.appendingPathComponent("mic.wav"))
        } catch {
            showAlert(title: "Impossible de démarrer", message: error.localizedDescription)
            return
        }

        let finishStart = { [weak self] in
            guard let self else { return }
            self.meetingMode = mode
            self.meetingDir = dir
            self.startInPersonItem.isHidden = true
            self.startRemoteItem.isHidden = true
            self.stopMeetingItem.isHidden = false
            self.updateStatusIcon()
            self.hud.show(mode == "remote" ? "🔴 Réunion Teams enregistrée" : "🔴 Réunion enregistrée")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.hud.hide() }
        }

        if mode == "remote" {
            // En plus du micro : l'audio système (les autres participants).
            systemAudio.start(to: dir.appendingPathComponent("system.caf")) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.meetingMic.stop()
                    self.showAlert(
                        title: "Capture de l'audio système impossible",
                        message: "Autorise Murmure dans Réglages Système → Confidentialité et sécurité → Enregistrement de l'écran, puis réessaie.\n\nDétail : \(error.localizedDescription)"
                    )
                    return
                }
                finishStart()
            }
        } else {
            finishStart()
        }
    }

    @objc private func stopMeeting() {
        guard let mode = meetingMode, let dir = meetingDir else { return }
        let micResult = meetingMic.stop()

        let proceed = { [weak self] (systemURL: URL?) in
            guard let self else { return }
            self.meetingMode = nil
            self.meetingDir = nil
            self.startInPersonItem.isHidden = false
            self.startRemoteItem.isHidden = false
            self.stopMeetingItem.isHidden = true
            self.updateStatusIcon()

            let title = self.askMeetingTitle()
            self.hud.show("⏳ Transcription de la réunion en cours…")
            self.backend.processMeeting(
                micURL: micResult?.url,
                systemURL: systemURL,
                mode: mode,
                title: title
            ) { result in
                self.hud.hide()
                switch result {
                case .success(let response):
                    let md = URL(fileURLWithPath: response.markdownPath)
                    NSWorkspace.shared.open(md)
                    NSWorkspace.shared.activateFileViewerSelecting([md])
                case .failure(let error):
                    self.showAlert(
                        title: "Échec de la transcription",
                        message: "\(error.localizedDescription)\n\nLes enregistrements audio sont conservés dans :\n\(dir.path)"
                    )
                }
            }
        }

        if mode == "remote" {
            systemAudio.stop { systemURL in proceed(systemURL) }
        } else {
            proceed(nil)
        }
    }

    private func askMeetingTitle() -> String {
        let alert = NSAlert()
        alert.messageText = "Titre de la réunion"
        alert.informativeText = "Ce titre sera utilisé pour nommer le compte-rendu."
        alert.addButton(withTitle: "Transcrire")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = "Réunion"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Réunion" : title
    }

    // MARK: - Backend

    private func checkBackendHealth() {
        backend.health { [weak self] healthy in
            guard let self else { return }
            self.backendHealthy = healthy
            self.backendStatusItem.title = healthy ? "Backend : ✅ en ligne" : "Backend : ❌ hors ligne"
            self.updateStatusIcon()
        }
    }

    /// Lance backend/run.sh. Le dossier backend est demandé au premier
    /// lancement puis mémorisé (UserDefaults "BackendDir").
    @objc private func startBackend() {
        if backendHealthy { return }
        guard let backendDir = resolveBackendDir() else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [backendDir.appendingPathComponent("run.sh").path]
        process.currentDirectoryURL = backendDir
        do {
            try process.run()
            backendProcess = process
            hud.show("⏳ Démarrage du backend (long au premier lancement)…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.hud.hide() }
        } catch {
            showAlert(title: "Impossible de lancer le backend", message: error.localizedDescription)
        }
    }

    private func resolveBackendDir() -> URL? {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "BackendDir") {
            let url = URL(fileURLWithPath: saved)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("run.sh").path) {
                return url
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choisis le dossier « backend » de Murmure"
        panel.message = "Sélectionne le dossier murmure/backend du projet (celui qui contient run.sh)."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("run.sh").path) else {
            showAlert(title: "Dossier invalide", message: "Ce dossier ne contient pas run.sh.")
            return nil
        }
        defaults.set(url.path, forKey: "BackendDir")
        return url
    }

    // MARK: - Préférences

    @objc private func toggleSounds() {
        soundsEnabled.toggle()
        soundsItem.state = soundsEnabled ? .on : .off
        UserDefaults.standard.set(soundsEnabled, forKey: "SoundsEnabled")
    }

    @objc private func toggleAutoLanguage() {
        autoLanguage.toggle()
        autoLanguageItem.state = autoLanguage ? .on : .off
        UserDefaults.standard.set(autoLanguage, forKey: "AutoLanguage")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(title: "Impossible de modifier le lancement automatique",
                      message: error.localizedDescription)
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - Divers

    @objc private func openOutputFolder() {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmure", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
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
