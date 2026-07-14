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

        if !UserDefaults.standard.bool(forKey: "didFirstRun") {
            UserDefaults.standard.set(true, forKey: "didFirstRun")
            Toast.shared.show(
                "Sablier enregistre en tâche de fond. Reviens ce soir voir ton rapport !",
                duration: 4
            )
        }
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

        // Bilan du jour, mis à jour à chaque ouverture du menu.
        let summaryItem = NSMenuItem(title: "Aujourd'hui : rien encore", action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        summaryItem.tag = 10
        menu.addItem(summaryItem)
        menu.addItem(.separator())

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

        let pauseHourItem = NSMenuItem(
            title: "Suspendre pendant 1 heure",
            action: #selector(pauseOneHour),
            keyEquivalent: ""
        )
        pauseHourItem.target = self
        pauseHourItem.tag = 4
        menu.addItem(pauseHourItem)

        let pauseTomorrowItem = NSMenuItem(
            title: "Suspendre jusqu'à demain",
            action: #selector(pauseUntilTomorrow),
            keyEquivalent: ""
        )
        pauseTomorrowItem.target = self
        pauseTomorrowItem.tag = 5
        menu.addItem(pauseTomorrowItem)

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

        let clearItem = NSMenuItem(
            title: "Effacer tout l'historique...",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)
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
            case 10:
                item.title = todaySummaryLine()
            case 1:
                item.title = sampler.isPaused ? "Reprendre le suivi" : "Suspendre le suivi"
                item.state = sampler.isPaused ? .on : .off
            case 4, 5:
                item.isEnabled = !sampler.isPaused
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

    /// "Aujourd'hui : 4 h 12, surtout Dev (1 h 50)".
    private func todaySummaryLine() -> String {
        let start = Calendar.current.startOfDay(for: Date())
        let sessions = Store.shared.sessions(from: start, to: Date())
        let total = sessions.reduce(0) { $0 + $1.duration }
        guard total > 60 else { return "Aujourd'hui : rien encore" }
        let rules = Categorizer.loadRules()
        var byCategory: [String: TimeInterval] = [:]
        for session in sessions {
            byCategory[Categorizer.category(for: session, rules: rules), default: 0]
                += session.duration
        }
        var line = "Aujourd'hui : \(formatDuration(total))"
        if let top = byCategory.max(by: { $0.value < $1.value }) {
            line += ", surtout \(top.key) (\(formatDuration(top.value)))"
        }
        return line
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

    @objc private func pauseOneHour() {
        sampler.setPaused(true, until: Date().addingTimeInterval(3600))
        Toast.shared.show("Suivi suspendu pendant 1 heure")
        updateStatusTitle()
    }

    @objc private func pauseUntilTomorrow() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())
        )!
        sampler.setPaused(true, until: tomorrow)
        Toast.shared.show("Suivi suspendu jusqu'à demain")
        updateStatusTitle()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Effacer tout l'historique ?"
        alert.informativeText = "Toutes les données de suivi seront définitivement "
            + "supprimées de ce Mac. Cette action est irréversible."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Tout effacer")
        alert.addButton(withTitle: "Annuler")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Store.shared.deleteAll()
            Toast.shared.show("Historique effacé")
            updateStatusTitle()
        }
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
