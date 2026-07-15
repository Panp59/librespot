import AppKit

/// Le bouton vedette : UN geste avant un partage d'écran, tout se met en
/// place ; le même geste après, tout revient comme avant. Chaque composant
/// n'est restauré que s'il a réellement été changé : si le bureau était
/// déjà masqué avant la démo, il le reste après.
final class DemoMode {
    static let shared = DemoMode()

    private(set) var isActive = false

    /// Ce qui devra être défait, sous forme de données (pas de closures) :
    /// à la sortie de l'app on doit pouvoir restaurer en SYNCHRONE, sinon
    /// les commandes asynchrones sont abandonnées à la mort du process.
    private enum RestoreAction {
        case menuBar(collapsed: Bool)
        case showDesktop
        case sleepAgain
        case focusOff
    }
    private var restoreActions: [RestoreAction] = []

    struct Settings {
        static var hidesMenuBarIcons: Bool {
            get { UserDefaults.standard.object(forKey: "demoHidesIcons") as? Bool ?? true }
            set { UserDefaults.standard.set(newValue, forKey: "demoHidesIcons") }
        }
        static var cleansDesktop: Bool {
            get { UserDefaults.standard.object(forKey: "demoCleansDesktop") as? Bool ?? true }
            set { UserDefaults.standard.set(newValue, forKey: "demoCleansDesktop") }
        }
        static var enablesFocus: Bool {
            get { UserDefaults.standard.object(forKey: "demoFocus") as? Bool ?? true }
            set { UserDefaults.standard.set(newValue, forKey: "demoFocus") }
        }
        static var keepsAwake: Bool {
            get { UserDefaults.standard.object(forKey: "demoAwake") as? Bool ?? true }
            set { UserDefaults.standard.set(newValue, forKey: "demoAwake") }
        }
    }

    func toggle() {
        isActive ? deactivate() : activate()
    }

    func activate() {
        guard !isActive else { return }
        restoreActions = []

        if Settings.hidesMenuBarIcons {
            let wasCollapsed = MenuBarConcealer.shared.isCollapsed
            MenuBarConcealer.shared.setCollapsed(true)
            restoreActions.append(.menuBar(collapsed: wasCollapsed))
        }

        if Settings.cleansDesktop, !DesktopIcons.cachedHidden {
            DesktopIcons.setHidden(true)
            restoreActions.append(.showDesktop)
        }

        if Settings.keepsAwake, !KeepAwake.shared.isOn {
            KeepAwake.shared.set(true)
            restoreActions.append(.sleepAgain)
        }

        if Settings.enablesFocus, !FocusMode.isOn {
            FocusMode.set(true) { ok in
                if !ok {
                    Toast.shared.show(
                        "Concentration non configurée (menu Régie > Configurer Ne pas déranger)"
                    )
                }
            }
            restoreActions.append(.focusOff)
        }

        isActive = true
        Toast.shared.show("Mode Démo activé. Bonne démo !")
    }

    /// `synchronously: true` uniquement à la sortie de l'app.
    func deactivate(synchronously: Bool = false) {
        guard isActive else { return }
        for action in restoreActions.reversed() {
            switch action {
            case .menuBar(let collapsed):
                MenuBarConcealer.shared.setCollapsed(collapsed)
            case .showDesktop:
                if synchronously {
                    DesktopIcons.setHiddenSync(false)
                } else {
                    DesktopIcons.setHidden(false)
                }
            case .sleepAgain:
                KeepAwake.shared.set(false)
            case .focusOff:
                if synchronously {
                    FocusMode.setSync(false)
                } else {
                    FocusMode.set(false)
                }
            }
        }
        restoreActions = []
        isActive = false
        if !synchronously {
            Toast.shared.show("Mode Démo désactivé, tout est revenu")
        }
    }
}
