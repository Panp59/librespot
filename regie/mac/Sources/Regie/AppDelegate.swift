import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        MenuBarConcealer.shared.install()
        DesktopIcons.refreshCache()
        Appearance.refreshCache()

        // Ctrl+Option+D : bascule du mode Démo, de n'importe où.
        HotKeyCenter.shared.register(
            keyCode: 2, // D
            modifiers: HotKeyCenter.control | HotKeyCenter.option
        ) {
            DemoMode.shared.toggle()
        }

        if !UserDefaults.standard.bool(forKey: "didFirstRun") {
            UserDefaults.standard.set(true, forKey: "didFirstRun")
            Toast.shared.show(
                "Régie est prête. Cmd-glisse les icônes à masquer à gauche du trait.",
                duration: 5
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Synchrone : les restaurations asynchrones seraient abandonnées
        // à la mort du process (bureau masqué et DND actifs pour toujours).
        if DemoMode.shared.isActive {
            DemoMode.shared.deactivate(synchronously: true)
        }
        KeepAwake.shared.set(false)
    }

    // MARK: barre de menus

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "regie-principal"
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "switch.2",
                accessibilityDescription: "Régie"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let demoItem = NSMenuItem(
            title: "Mode Démo",
            action: #selector(toggleDemo),
            keyEquivalent: "d"
        )
        demoItem.keyEquivalentModifierMask = [.control, .option]
        demoItem.target = self
        demoItem.tag = 1
        menu.addItem(demoItem)
        menu.addItem(.separator())

        menu.addItem(makeToggle("Masquer les icônes secondaires", #selector(toggleIcons), tag: 2))
        menu.addItem(makeToggle("Bureau propre (fichiers masqués)", #selector(toggleDesktop), tag: 3))
        menu.addItem(makeToggle("Ne pas déranger", #selector(toggleFocus), tag: 4))
        menu.addItem(makeToggle("Garder le Mac éveillé", #selector(toggleAwake), tag: 5))
        menu.addItem(makeToggle("Apparence sombre", #selector(toggleDark), tag: 6))
        menu.addItem(.separator())

        let demoSettingsItem = NSMenuItem(title: "Le mode Démo active", action: nil, keyEquivalent: "")
        let demoSettings = NSMenu()
        demoSettings.autoenablesItems = false
        demoSettings.addItem(makeToggle("Icônes masquées", #selector(toggleDemoIcons), tag: 21))
        demoSettings.addItem(makeToggle("Bureau propre", #selector(toggleDemoDesktop), tag: 22))
        demoSettings.addItem(makeToggle("Ne pas déranger", #selector(toggleDemoFocus), tag: 23))
        demoSettings.addItem(makeToggle("Mac éveillé", #selector(toggleDemoAwake), tag: 24))
        demoSettingsItem.submenu = demoSettings
        menu.addItem(demoSettingsItem)

        let focusSetupItem = NSMenuItem(
            title: "Configurer Ne pas déranger...",
            action: #selector(setupFocus),
            keyEquivalent: ""
        )
        focusSetupItem.target = self
        menu.addItem(focusSetupItem)

        let loginItem = NSMenuItem(
            title: "Lancer au démarrage",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.tag = 7
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "À propos de Régie", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(
            title: "Quitter Régie",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        item.menu = menu
        statusItem = item
    }

    private func makeToggle(_ title: String, _ action: Selector, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusItem?.menu {
            // Rafraîchit les caches en arrière-plan : si l'état a changé
            // hors de Régie, la prochaine ouverture sera juste.
            DesktopIcons.refreshCache()
            Appearance.refreshCache()
        }
        for item in menu.items {
            switch item.tag {
            case 1:
                item.state = DemoMode.shared.isActive ? .on : .off
                item.title = DemoMode.shared.isActive
                    ? "Mode Démo (actif)" : "Mode Démo"
            case 2: item.state = MenuBarConcealer.shared.isCollapsed ? .on : .off
            case 3: item.state = DesktopIcons.cachedHidden ? .on : .off
            case 4: item.state = FocusMode.isOn ? .on : .off
            case 5: item.state = KeepAwake.shared.isOn ? .on : .off
            case 6: item.state = Appearance.cachedDark ? .on : .off
            case 7: item.state = SMAppService.mainApp.status == .enabled ? .on : .off
            case 21: item.state = DemoMode.Settings.hidesMenuBarIcons ? .on : .off
            case 22: item.state = DemoMode.Settings.cleansDesktop ? .on : .off
            case 23: item.state = DemoMode.Settings.enablesFocus ? .on : .off
            case 24: item.state = DemoMode.Settings.keepsAwake ? .on : .off
            default: break
            }
            if let submenu = item.submenu {
                menuNeedsUpdate(submenu)
            }
        }
    }

    // MARK: actions

    @objc private func toggleDemo() { DemoMode.shared.toggle() }

    @objc private func toggleIcons() {
        MenuBarConcealer.shared.setCollapsed(!MenuBarConcealer.shared.isCollapsed)
    }

    @objc private func toggleDesktop() {
        let hide = !DesktopIcons.cachedHidden
        DesktopIcons.setHidden(hide) {
            Toast.shared.show(hide
                ? "Fichiers du bureau masqués"
                : "Fichiers du bureau affichés")
        }
    }

    @objc private func toggleFocus() {
        let on = !FocusMode.isOn
        FocusMode.set(on) { ok in
            if ok {
                Toast.shared.show(on ? "Ne pas déranger activé" : "Ne pas déranger désactivé")
            } else {
                FocusMode.showSetupInstructions()
            }
        }
    }

    @objc private func toggleAwake() {
        let on = !KeepAwake.shared.isOn
        KeepAwake.shared.set(on)
        Toast.shared.show(on
            ? "Le Mac restera éveillé"
            : "Mise en veille normale rétablie")
    }

    @objc private func toggleDark() {
        Appearance.setDark(!Appearance.cachedDark)
    }

    @objc private func toggleDemoIcons() {
        DemoMode.Settings.hidesMenuBarIcons.toggle()
    }
    @objc private func toggleDemoDesktop() {
        DemoMode.Settings.cleansDesktop.toggle()
    }
    @objc private func toggleDemoFocus() {
        DemoMode.Settings.enablesFocus.toggle()
    }
    @objc private func toggleDemoAwake() {
        DemoMode.Settings.keepsAwake.toggle()
    }

    @objc private func setupFocus() {
        FocusMode.showSetupInstructions()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
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

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Régie"
        alert.informativeText = """
        Le poste de commande du Mac : icônes de la barre de menus, bureau, \
        concentration, veille, apparence. Et le mode Démo (Ctrl+Option+D) \
        qui prépare tout avant un partage d'écran, puis remet tout en place.

        Pour ranger des icônes : maintiens Cmd et glisse-les à GAUCHE du \
        trait Régie, puis replie avec le chevron.

        Fait maison chez ADTI.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
