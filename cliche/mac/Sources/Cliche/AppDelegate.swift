import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let captureManager = CaptureManager()
    private var recentMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: Settings.defaults)
        setupStatusItem()
        registerHotkeys()
    }

    // MARK: barre de menus

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "Cliché"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(makeItem("Capturer une zone", #selector(captureArea), key: "7"))
        menu.addItem(makeItem("Capturer une fenêtre", #selector(captureWindow), key: "8"))
        menu.addItem(makeItem("Capturer l'écran", #selector(captureScreen), key: "9"))
        menu.addItem(.separator())

        let recentItem = NSMenuItem(title: "Captures récentes", action: nil, keyEquivalent: "")
        let recentSubmenu = NSMenu()
        recentItem.submenu = recentSubmenu
        recentMenu = recentSubmenu
        menu.addItem(recentItem)

        let folderItem = NSMenuItem(
            title: "Ouvrir le dossier des captures",
            action: #selector(openFolder),
            keyEquivalent: ""
        )
        folderItem.target = self
        menu.addItem(folderItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Réglages", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.addItem(makeToggle("Copier automatiquement", #selector(toggleAutoCopy), tag: 1))
        settingsMenu.addItem(makeToggle("Carte d'actions rapides", #selector(toggleQuickActions), tag: 2))
        settingsMenu.addItem(makeToggle("Son de capture", #selector(toggleSound), tag: 3))
        settingsMenu.addItem(makeToggle("Ombre des fenêtres", #selector(toggleShadow), tag: 4))
        settingsMenu.addItem(.separator())
        settingsMenu.addItem(makeToggle("Lancer au démarrage", #selector(toggleLaunchAtLogin), tag: 5))
        settingsMenu.addItem(.separator())
        let dirItem = NSMenuItem(
            title: "Dossier de sauvegarde...",
            action: #selector(chooseFolder),
            keyEquivalent: ""
        )
        dirItem.target = self
        settingsMenu.addItem(dirItem)
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "À propos de Cliché", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(title: "Quitter Cliché", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        return item
    }

    private func makeToggle(_ title: String, _ action: Selector, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    /// Rafraîchit les coches des réglages et la liste des captures récentes
    /// à chaque ouverture du menu.
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            switch item.tag {
            case 1: item.state = Settings.autoCopy ? .on : .off
            case 2: item.state = Settings.quickActions ? .on : .off
            case 3: item.state = Settings.captureSound ? .on : .off
            case 4: item.state = Settings.windowShadow ? .on : .off
            case 5: item.state = launchAtLoginEnabled ? .on : .off
            default: break
            }
            if let submenu = item.submenu {
                menuNeedsUpdate(submenu)
            }
        }
        if menu === statusItem?.menu {
            refreshRecentMenu()
        }
    }

    private func refreshRecentMenu() {
        guard let recentMenu else { return }
        recentMenu.removeAllItems()
        let dir = Settings.saveDirectory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let images = files
            .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            .prefix(6)

        if images.isEmpty {
            let empty = NSMenuItem(title: "Aucune capture", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
            return
        }
        for url in images {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            recentMenu.addItem(item)
        }
    }

    // MARK: raccourcis globaux

    private func registerHotkeys() {
        let mods = HotKeyCenter.cmd | HotKeyCenter.shift
        HotKeyCenter.shared.register(keyCode: 26, modifiers: mods) { [weak self] in // 7
            self?.startCapture(.area)
        }
        HotKeyCenter.shared.register(keyCode: 28, modifiers: mods) { [weak self] in // 8
            self?.startCapture(.window)
        }
        HotKeyCenter.shared.register(keyCode: 25, modifiers: mods) { [weak self] in // 9
            self?.startCapture(.screen)
        }
    }

    // MARK: capture

    @objc private func captureArea() { startCapture(.area) }
    @objc private func captureWindow() { startCapture(.window) }
    @objc private func captureScreen() { startCapture(.screen) }

    private func startCapture(_ mode: CaptureManager.Mode) {
        captureManager.capture(mode: mode) { [weak self] url in
            guard let url else { return } // annulé
            self?.handleCapture(url)
        }
    }

    private func handleCapture(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            Toast.shared.show("Capture illisible : \(url.lastPathComponent)")
            return
        }
        if Settings.autoCopy {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
        if Settings.quickActions {
            QuickActionsPanel.show(fileURL: url, image: image)
        } else {
            Toast.shared.show(Settings.autoCopy
                ? "Capture enregistrée et copiée"
                : "Capture enregistrée")
        }
    }

    // MARK: actions du menu

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        AnnotatorWindowController.open(fileURL: url)
    }

    @objc private func openFolder() {
        let dir = Settings.saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func toggleAutoCopy() { Settings.autoCopy.toggle() }
    @objc private func toggleQuickActions() { Settings.quickActions.toggle() }
    @objc private func toggleSound() { Settings.captureSound.toggle() }
    @objc private func toggleShadow() { Settings.windowShadow.toggle() }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
                Toast.shared.show("Lancement au démarrage désactivé")
            } else {
                try SMAppService.mainApp.register()
                Toast.shared.show("Lancement au démarrage activé")
            }
        } catch {
            Toast.shared.show("Impossible de modifier le lancement au démarrage")
        }
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Dossier où enregistrer les captures"
        panel.directoryURL = Settings.saveDirectory
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            Settings.saveDirectory = url
            Toast.shared.show("Captures enregistrées dans \(url.lastPathComponent)")
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Cliché"
        alert.informativeText = """
        Capture d'écran locale : zone, fenêtre ou écran entier, \
        annotation, texte (OCR), épinglage et joli fond.

        Raccourcis : ⇧⌘7 zone, ⇧⌘8 fenêtre, ⇧⌘9 écran.

        Tout reste sur ce Mac. Fait maison chez ADTI.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
