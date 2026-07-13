import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let sampler = Sampler()
    private var menuBarTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Categorizer.ensureRulesFile()
        setupStatusItem()
        sampler.start()

        menuBarTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateStatusTitle()
        }
        updateStatusTitle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sampler.flush()
    }

    // MARK: barre de menus

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "hourglass",
                accessibilityDescription: "Sablier"
            )
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let reportItem = NSMenuItem(
            title: "Ouvrir le rapport",
            action: #selector(openReport),
            keyEquivalent: ""
        )
        reportItem.target = self
        menu.addItem(reportItem)
        menu.addItem(.separator())

        let pauseItem = NSMenuItem(
            title: "Suspendre le suivi",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pauseItem.target = self
        pauseItem.tag = 1
        menu.addItem(pauseItem)

        let axItem = NSMenuItem(
            title: "Activer les titres de fenêtres (Accessibilité)",
            action: #selector(enableAccessibility),
            keyEquivalent: ""
        )
        axItem.target = self
        axItem.tag = 2
        menu.addItem(axItem)

        let loginItem = NSMenuItem(
            title: "Lancer au démarrage",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.tag = 3
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let rulesItem = NSMenuItem(
            title: "Modifier les règles de catégories...",
            action: #selector(openRules),
            keyEquivalent: ""
        )
        rulesItem.target = self
        menu.addItem(rulesItem)

        let dataItem = NSMenuItem(
            title: "Afficher les données (dossier local)",
            action: #selector(openDataFolder),
            keyEquivalent: ""
        )
        dataItem.target = self
        menu.addItem(dataItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "À propos de Sablier", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(
            title: "Quitter Sablier",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            switch item.tag {
            case 1:
                item.state = sampler.isPaused ? .on : .off
            case 2:
                item.state = Sampler.accessibilityGranted ? .on : .off
                item.isEnabled = !Sampler.accessibilityGranted
            case 3:
                item.state = SMAppService.mainApp.status == .enabled ? .on : .off
            default:
                break
            }
        }
        updateStatusTitle()
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        if sampler.isPaused {
            button.title = " en pause"
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let total = Store.shared.totalDuration(from: start, to: Date())
        button.title = total > 0 ? " \(formatDuration(total))" : ""
    }

    // MARK: actions

    @objc private func openReport() {
        ReportWindowController.shared.show()
    }

    @objc private func togglePause() {
        sampler.setPaused(!sampler.isPaused)
        Toast.shared.show(sampler.isPaused
            ? "Suivi suspendu (rien n'est enregistré)"
            : "Suivi repris")
        updateStatusTitle()
    }

    @objc private func enableAccessibility() {
        Sampler.promptForAccessibility()
        Toast.shared.show("Ajoute Sablier dans Confidentialité > Accessibilité")
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

    @objc private func openRules() {
        Categorizer.ensureRulesFile()
        NSWorkspace.shared.open(Categorizer.rulesFileURL)
    }

    @objc private func openDataFolder() {
        NSWorkspace.shared.open(Store.dataDirectory)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Sablier"
        alert.informativeText = """
        Suivi du temps automatique et 100% local : quelle app, quel \
        document, pendant combien de temps. Aucune saisie, aucune donnée \
        ne quitte ce Mac.

        Le temps affiché dans la barre de menus est le temps actif du jour \
        (les absences de plus de 3 minutes ne comptent pas).

        Fait maison chez ADTI.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
