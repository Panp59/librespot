import AppKit
import ApplicationServices

/// Le capteur : toutes les 5 secondes, note l'app au premier plan (et le
/// titre de sa fenêtre si l'autorisation Accessibilité est accordée).
/// Les échantillons consécutifs identiques sont fusionnés en sessions.
/// Conçu pour les journées fragmentées : aucun coût à changer de contexte
/// cent fois par jour, c'est même ce qu'on veut mesurer.
final class Sampler {
    static let tickInterval: TimeInterval = 5
    static let idleThreshold: TimeInterval = 180 // 3 min sans clavier/souris = absent

    private(set) var isPaused = false {
        didSet { if isPaused { closeCurrentSession(at: Date()) } }
    }

    private var timer: Timer?
    private var current: (id: Int64, session: WorkSession)?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 1

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self, selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(sessionResigned),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil
        )
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    /// À appeler avant de quitter : ferme proprement la session en cours.
    func flush() {
        closeCurrentSession(at: Date())
    }

    @objc private func systemWillSleep() { closeCurrentSession(at: Date()) }
    @objc private func sessionResigned() { closeCurrentSession(at: Date()) }

    private func tick() {
        guard !isPaused else { return }
        let now = Date()

        // Inactivité : on regarde le temps écoulé depuis le dernier événement
        // d'entrée, tous types confondus.
        let idle = Self.idleSeconds()
        if idle >= Self.idleThreshold {
            // L'utilisateur est parti : la session s'arrête au moment du
            // dernier geste, pas maintenant.
            closeCurrentSession(at: now.addingTimeInterval(-idle))
            return
        }

        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            closeCurrentSession(at: now)
            return
        }
        var bundle = frontmost.bundleIdentifier ?? "inconnu"
        var app = frontmost.localizedName ?? bundle
        var title = Self.focusedWindowTitle(pid: frontmost.processIdentifier) ?? ""

        // Multi-écrans : macOS fait défiler la fenêtre sous la souris sans
        // lui donner le focus. Si le dernier geste est un défilement et que
        // la souris survole la fenêtre d'une AUTRE app, c'est elle qu'on lit
        // réellement : on attribue le temps à l'app sous le pointeur.
        let scrollIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: .scrollWheel
        )
        let keyIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: .keyDown
        )
        let clickIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: .leftMouseDown
        )
        if scrollIdle < Self.tickInterval, scrollIdle < keyIdle, scrollIdle < clickIdle,
           let pointed = Self.appUnderPointer(),
           pointed.processIdentifier != frontmost.processIdentifier {
            bundle = pointed.bundleIdentifier ?? "inconnu"
            app = pointed.localizedName ?? bundle
            // Pas de titre fiable pour une fenêtre non focalisée : on reste
            // au niveau de l'app plutôt que de risquer un faux titre.
            title = ""
        }

        if var open = current {
            if open.session.bundle == bundle && open.session.title == title {
                // Même contexte : on prolonge.
                open.session.end = now
                current = open
                Store.shared.updateEnd(id: open.id, end: now)
                return
            }
            closeCurrentSession(at: now)
        }

        // Nouveau contexte : on ouvre une session.
        var session = WorkSession(start: now, end: now, bundle: bundle, app: app, title: title)
        let id = Store.shared.insert(session)
        session.id = id
        current = (id, session)
    }

    private func closeCurrentSession(at date: Date) {
        guard let open = current else { return }
        let end = max(open.session.start, date)
        Store.shared.updateEnd(id: open.id, end: end)
        current = nil
    }

    /// Secondes depuis le dernier événement clavier/souris/molette.
    static func idleSeconds() -> TimeInterval {
        let types: [CGEventType] = [
            .keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown,
            .scrollWheel, .leftMouseDragged,
        ]
        let values = types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }
        return values.min() ?? 0
    }

    /// Titre de la fenêtre au premier plan, si l'Accessibilité est accordée.
    /// Sans l'autorisation, retourne nil : Sablier fonctionne quand même,
    /// juste avec un grain plus grossier (l'app sans le document).
    static func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowValue
        ) == .success, let windowValue else { return nil }
        let window = windowValue as! AXUIElement
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window, kAXTitleAttribute as CFString, &titleValue
        ) == .success else { return nil }
        return titleValue as? String
    }

    /// L'application propriétaire de la fenêtre sous le pointeur.
    /// Les positions de fenêtres sont publiques (aucune autorisation) ;
    /// seuls leurs TITRES exigeraient Enregistrement de l'écran, on s'en passe.
    static func appUnderPointer() -> NSRunningApplication? {
        let mouse = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first else { return nil }
        // NSEvent.mouseLocation a l'origine en BAS à gauche de l'écran
        // principal, les fenêtres CGWindow en HAUT à gauche.
        let point = CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)

        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        // La liste est ordonnée du premier plan vers l'arrière : la première
        // fenêtre normale (layer 0) qui contient le point gagne.
        for window in info {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point),
                  let pid = window[kCGWindowOwnerPID as String] as? Int
            else { continue }
            return NSRunningApplication(processIdentifier: pid_t(pid))
        }
        return nil
    }

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Ouvre la demande d'autorisation Accessibilité (dialogue système).
    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
