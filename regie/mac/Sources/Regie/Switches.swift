import AppKit

/// Petit utilitaire d'exécution de commandes système.
enum Shell {
    /// Exécution synchrone courte (lectures d'état). À réserver aux
    /// commandes instantanées comme `defaults read`.
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Exécution détachée (actions), avec retour optionnel sur le main thread.
    static func runAsync(
        _ path: String, _ arguments: [String],
        completion: ((Int32) -> Void)? = nil
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let status = process.terminationStatus
                DispatchQueue.main.async { completion?(status) }
            } catch {
                DispatchQueue.main.async { completion?(-1) }
            }
        }
    }
}

/// Les fichiers du bureau : Finder sait ne plus les dessiner.
enum DesktopIcons {
    static var isHidden: Bool {
        let value = Shell.run("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"])
        return value == "0" || value.lowercased() == "false"
    }

    static func setHidden(_ hidden: Bool, completion: (() -> Void)? = nil) {
        Shell.runAsync("/usr/bin/defaults", [
            "write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true",
        ]) { _ in
            Shell.runAsync("/usr/bin/killall", ["Finder"]) { _ in completion?() }
        }
    }
}

/// Maintien éveillé via le caffeinate système, tué à l'extinction.
final class KeepAwake {
    static let shared = KeepAwake()
    private var process: Process?

    var isOn: Bool { process?.isRunning == true }

    func set(_ on: Bool) {
        if on {
            guard !isOn else { return }
            let caffeinate = Process()
            caffeinate.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            caffeinate.arguments = ["-dis"]
            do {
                try caffeinate.run()
                process = caffeinate
            } catch {
                Toast.shared.show("Impossible de lancer caffeinate")
            }
        } else {
            process?.terminate()
            process = nil
        }
    }
}

/// Apparence sombre/claire, via System Events (autorisation Automation
/// demandée par macOS au premier usage).
enum Appearance {
    static var isDark: Bool {
        Shell.run("/usr/bin/defaults", ["read", "-g", "AppleInterfaceStyle"]) == "Dark"
    }

    static func setDark(_ dark: Bool) {
        let source = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to \(dark ? "true" : "false")
            end tell
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if error != nil {
                DispatchQueue.main.async {
                    Toast.shared.show(
                        "Autorise Régie dans Confidentialité > Automatisation"
                    )
                }
            }
        }
    }
}

/// Ne pas déranger. macOS n'offre aucune API publique : on passe par
/// l'app Raccourcis, la seule voie officielle. L'utilisateur crée une
/// fois deux raccourcis nommés ci-dessous (action "Définir le mode de
/// concentration"), Régie les déclenche ensuite.
enum FocusMode {
    static let onShortcut = "Régie Concentration On"
    static let offShortcut = "Régie Concentration Off"

    private(set) static var isOn = false

    static var shortcutsConfigured: Bool {
        let list = Shell.run("/usr/bin/shortcuts", ["list"])
        return list.contains(onShortcut) && list.contains(offShortcut)
    }

    static func set(_ on: Bool, completion: ((Bool) -> Void)? = nil) {
        let name = on ? onShortcut : offShortcut
        Shell.runAsync("/usr/bin/shortcuts", ["run", name]) { status in
            if status == 0 {
                isOn = on
                completion?(true)
            } else {
                completion?(false)
            }
        }
    }

    /// Alerte pas à pas pour créer les deux raccourcis, avec ouverture
    /// directe de l'app Raccourcis.
    static func showSetupInstructions() {
        let alert = NSAlert()
        alert.messageText = "Configurer Ne pas déranger"
        alert.informativeText = """
        macOS ne laisse pas les apps toucher directement à la concentration. \
        Il faut créer deux raccourcis, une seule fois :

        1. Ouvre l'app Raccourcis
        2. Nouveau raccourci, ajoute l'action « Définir le mode de concentration », \
        choisis « Activer » Ne pas déranger, nomme-le exactement :
        \(onShortcut)
        3. Pareil avec « Désactiver », nommé :
        \(offShortcut)

        Ensuite Régie (et son mode Démo) les déclenchera tout seul.
        """
        alert.addButton(withTitle: "Ouvrir Raccourcis")
        alert.addButton(withTitle: "Plus tard")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
        }
    }
}
