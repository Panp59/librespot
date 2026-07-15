import AppKit

/// Le bouton vedette : UN geste avant un partage d'écran, tout se met en
/// place ; le même geste après, tout revient comme avant. Chaque composant
/// mémorise l'état antérieur : si le bureau était déjà masqué, il le reste
/// en sortant du mode Démo.
final class DemoMode {
    static let shared = DemoMode()

    private(set) var isActive = false
    private var restoreActions: [() -> Void] = []

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
            restoreActions.append { MenuBarConcealer.shared.setCollapsed(wasCollapsed) }
        }

        if Settings.cleansDesktop {
            let wasHidden = DesktopIcons.isHidden
            if !wasHidden {
                DesktopIcons.setHidden(true)
                restoreActions.append { DesktopIcons.setHidden(false) }
            }
        }

        if Settings.keepsAwake {
            let wasOn = KeepAwake.shared.isOn
            KeepAwake.shared.set(true)
            if !wasOn {
                restoreActions.append { KeepAwake.shared.set(false) }
            }
        }

        if Settings.enablesFocus {
            FocusMode.set(true) { ok in
                if !ok {
                    Toast.shared.show(
                        "Concentration non configurée (menu Régie > Configurer Ne pas déranger)"
                    )
                }
            }
            restoreActions.append { FocusMode.set(false) }
        }

        isActive = true
        Toast.shared.show("Mode Démo activé. Bonne démo !")
    }

    func deactivate() {
        guard isActive else { return }
        for restore in restoreActions.reversed() {
            restore()
        }
        restoreActions = []
        isActive = false
        Toast.shared.show("Mode Démo désactivé, tout est revenu")
    }
}
