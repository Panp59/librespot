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
    private let notesWindow = NotesWindow()

    private var healthTimer: Timer?
    private var backendHealthy = false
    private var backendStarting = false
    private var backendProcess: Process?
    private var lastAutoStartAt: Date?

    private var meetingMode: String? // "in_person" | "remote", nil = pas de réunion
    private var meetingDir: URL?
    private var meetingsWindow: MeetingsWindowController?

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
    private var notesMenuItem: NSMenuItem!

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
        menu.addItem(NSMenuItem(
            title: "Afficher les logs du backend", action: #selector(openBackendLog), keyEquivalent: "l"
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
        notesMenuItem = NSMenuItem(
            title: "Afficher les notes de réunion",
            action: #selector(showNotes), keyEquivalent: "n"
        )
        notesMenuItem.isHidden = true
        menu.addItem(notesMenuItem)

        let meetingsItem = NSMenuItem(
            title: "Réunions enregistrées…",
            action: #selector(showMeetingsWindow), keyEquivalent: "l"
        )
        menu.addItem(meetingsItem)
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
        let fallback: String
        if meetingMode != nil {
            symbolName = "record.circle.fill"
            fallback = "record.circle.fill"
        } else if backendHealthy {
            symbolName = "waveform"
            fallback = "mic.fill"
        } else {
            symbolName = "waveform.slash"
            fallback = "mic.slash"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Murmure")
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: "Murmure")
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
            if backendStarting {
                hud.show("Le backend démarre, quelques secondes…", style: .working)
            } else {
                hud.show("Backend hors ligne (menu Murmure → Démarrer le backend)", style: .error)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.hud.hide() }
            return
        }
        guard !dictationMic.isRecording else { return }
        do {
            try dictationMic.start(to: dictationFileURL)
            dictationCancelled = false
            installEscapeMonitors()
            playSound("Tink")
            hud.show("Je t'écoute… (Échap pour annuler)", style: .recording)
        } catch {
            hud.show("Micro indisponible", style: .error)
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
        hud.show("Transcription…", style: .working)
        backend.dictate(audioURL: url, language: autoLanguage ? "auto" : nil) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text) where !text.isEmpty:
                self.hud.hide()
                self.deliverDictation(text)
            case .success:
                self.hud.show("Rien entendu")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.hud.hide() }
            case .failure(let error):
                self.hud.show("Erreur de transcription", style: .error)
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

    private var accessibilityAlertShown = false

    /// Insère le texte au curseur si l'Accessibilité est accordée ; sinon
    /// le copie dans le presse-papiers et guide vers le bon réglage
    /// (l'autorisation saute à chaque rebuild : signature ad hoc).
    private func deliverDictation(_ text: String) {
        if AXIsProcessTrusted() {
            playSound("Pop")
            TextInserter.insertAtCursor(text)
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        playSound("Pop")
        hud.show("Texte copié : colle avec ⌘V (Accessibilité requise pour l'insertion auto)", style: .error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.hud.hide() }

        if !accessibilityAlertShown {
            accessibilityAlertShown = true
            promptAccessibility()
        }
    }

    private func promptAccessibility() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Autorisation Accessibilité requise"
        alert.informativeText = """
        Pour insérer le texte dicté au curseur, macOS exige l'autorisation \
        Accessibilité.

        Réglages Système → Confidentialité et sécurité → Accessibilité → \
        active Murmure. Si Murmure y figure déjà, retire-le (bouton –) puis \
        re-ajoute /Applications/Murmure.app : l'autorisation se perd quand \
        l'app est reconstruite.

        En attendant, chaque dictée est copiée dans le presse-papiers : \
        colle-la avec ⌘V.
        """
        alert.addButton(withTitle: "Ouvrir les réglages")
        alert.addButton(withTitle: "Plus tard")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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
            self.notesMenuItem.isHidden = false
            self.notesWindow.reset()
            self.notesWindow.show()
            self.updateStatusIcon()
            self.hud.show(mode == "remote" ? "Réunion Teams en cours d'enregistrement" : "Réunion en cours d'enregistrement", style: .recording)
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

        let notes = notesWindow.text
        notesWindow.close()

        let proceed = { [weak self] (systemURL: URL?) in
            guard let self else { return }
            self.meetingMode = nil
            self.meetingDir = nil
            self.startInPersonItem.isHidden = false
            self.startRemoteItem.isHidden = false
            self.stopMeetingItem.isHidden = true
            self.notesMenuItem.isHidden = true
            self.updateStatusIcon()

            let title = self.askMeetingTitle()

            // Synchronisation des pistes : le micro et l'audio système ne
            // démarrent pas exactement au même instant.
            var micOffset = 0.0
            var systemOffset = 0.0
            if mode == "remote",
               let micStart = self.meetingMic.startTime,
               let systemStart = self.systemAudio.firstSampleTime {
                let reference = min(micStart, systemStart)
                micOffset = micStart - reference
                systemOffset = systemStart - reference
            }

            self.hud.show("Transcription de la réunion en cours…", style: .working)
            self.backend.processMeeting(
                micURL: micResult?.url,
                systemURL: systemURL,
                mode: mode,
                title: title,
                micOffset: micOffset,
                systemOffset: systemOffset,
                notes: notes
            ) { result in
                self.hud.hide()
                switch result {
                case .success(let response):
                    // Mémorise où est parti le résultat, pour que la fenêtre
                    // « Réunions enregistrées » sache que c'est fait.
                    MeetingRecording.writeOutputLink(response.outputDir, in: dir)
                    // Ouvre le compte-rendu s'il a pu être généré (Ollama),
                    // sinon la transcription complète.
                    let md = URL(fileURLWithPath: response.summaryPath ?? response.markdownPath)
                    NSWorkspace.shared.open(md)
                    NSWorkspace.shared.activateFileViewerSelecting([md])
                    if let summaryError = response.summaryError {
                        NSLog("Murmure: compte-rendu indisponible: \(summaryError)")
                    }
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

    /// Fenêtre de gestion des réunions : liste des enregistrements, état de
    /// leur transcription, et relance. Indispensable quand la transcription
    /// n'a pas pu se faire (Mac en veille, écran fermé) : l'audio est
    /// conservé, on relance quand on veut.
    @objc private func showMeetingsWindow() {
        if meetingsWindow == nil {
            meetingsWindow = MeetingsWindowController(
                recordingsDir: recordingsDir,
                backend: backend
            ) { [weak self] recording, title, finished in
                self?.reprocess(recording, title: title, completion: finished)
            }
        }
        meetingsWindow?.show()
    }

    private func reprocess(
        _ recording: MeetingRecording, title: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard meetingMode == nil else {
            showAlert(title: "Réunion en cours",
                      message: "Termine la réunion en cours avant d'en retranscrire une autre.")
            completion(false)
            return
        }
        guard backendHealthy else {
            showAlert(title: "Backend hors ligne",
                      message: "Démarre le backend (menu Murmure) avant de retranscrire.")
            completion(false)
            return
        }

        hud.show("Retranscription en cours…", style: .working)
        backend.processMeeting(
            micURL: recording.micURL,
            systemURL: recording.systemURL,
            mode: recording.mode,
            title: title
        ) { [weak self] result in
            guard let self else { return }
            self.hud.hide()
            switch result {
            case .success(let response):
                MeetingRecording.writeOutputLink(response.outputDir, in: recording.directory)
                let md = URL(fileURLWithPath: response.summaryPath ?? response.markdownPath)
                NSWorkspace.shared.open(md)
                completion(true)
            case .failure(let error):
                self.showAlert(
                    title: "Échec de la transcription",
                    message: "\(error.localizedDescription)\n\nLes fichiers audio restent dans :\n\(recording.directory.path)"
                )
                completion(false)
            }
        }
    }

    // MARK: - Backend

    private func checkBackendHealth() {
        backend.health { [weak self] healthy in
            guard let self else { return }
            self.backendHealthy = healthy
            if healthy { self.backendStarting = false }
            self.backendStatusItem.title = healthy
                ? "Backend : ✅ en ligne"
                : self.backendStarting ? "Backend : ⏳ démarrage…" : "Backend : ❌ hors ligne"
            self.updateStatusIcon()
            self.autoStartBackendIfNeeded(healthy: healthy)
        }
    }

    /// Backend embarqué dans le bundle (make_app.sh le copie dans Resources).
    private func bundledBackendDir() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let dir = resources.appendingPathComponent("backend", isDirectory: true)
        let hasRunScript = FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("run.sh").path
        )
        return hasRunScript ? dir : nil
    }

    private func savedBackendDir() -> URL? {
        guard let saved = UserDefaults.standard.string(forKey: "BackendDir") else { return nil }
        let url = URL(fileURLWithPath: saved)
        let hasRunScript = FileManager.default.fileExists(
            atPath: url.appendingPathComponent("run.sh").path
        )
        return hasRunScript ? url : nil
    }

    /// Démarrage automatique : dès que le backend est injoignable et
    /// qu'aucun processus lancé par l'app ne tourne, on (re)lance run.sh.
    /// Garde-fou de 30 s pour ne pas boucler si le démarrage échoue.
    private func autoStartBackendIfNeeded(healthy: Bool) {
        guard !healthy else { return }
        if let process = backendProcess, process.isRunning { return }
        if let last = lastAutoStartAt, Date().timeIntervalSince(last) < 30 { return }
        guard let dir = bundledBackendDir() ?? savedBackendDir() else { return }
        lastAutoStartAt = Date()
        launchBackend(from: dir)
    }

    /// Journal du backend : ~/Library/Logs/Murmure/backend.log
    private var backendLogURL: URL {
        let dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Murmure", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("backend.log")
    }

    private func launchBackend(from dir: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [dir.appendingPathComponent("run.sh").path]

        // Toute la sortie du backend part dans le journal (sinon elle est
        // perdue : un process lancé depuis une app n'a pas de terminal).
        let logURL = backendLogURL
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            let formatter = ISO8601DateFormatter()
            handle.write(Data("\n===== Lancement du backend \(formatter.string(from: Date())) =====\n".utf8))
            process.standardOutput = handle
            process.standardError = handle
        }
        process.terminationHandler = { [weak self] finished in
            NSLog("Murmure: backend terminé (code \(finished.terminationStatus))")
            DispatchQueue.main.async { self?.backendStarting = false }
        }

        do {
            try process.run()
            backendProcess = process
            backendStarting = true
            backendStatusItem.title = "Backend : ⏳ démarrage…"
        } catch {
            NSLog("Murmure: lancement du backend impossible: \(error)")
        }
    }

    @objc private func openBackendLog() {
        NSWorkspace.shared.open(backendLogURL)
    }

    /// Action du menu : utile seulement si le backend n'est ni embarqué ni
    /// mémorisé (l'app le démarre toute seule sinon).
    @objc private func startBackend() {
        if backendHealthy { return }
        guard let backendDir = resolveBackendDir() else { return }
        launchBackend(from: backendDir)
        hud.show("Démarrage du backend (long au premier lancement)…", style: .working)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.hud.hide() }
    }

    private func resolveBackendDir() -> URL? {
        if let bundled = bundledBackendDir() { return bundled }
        if let saved = savedBackendDir() { return saved }

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
        UserDefaults.standard.set(url.path, forKey: "BackendDir")
        return url
    }

    @objc private func showNotes() {
        notesWindow.show()
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
