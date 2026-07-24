import AppKit
import ApplicationServices
import CoreServices

/// Le capteur : toutes les 5 secondes, note l'app au premier plan (et le
/// titre de sa fenêtre si l'autorisation Accessibilité est accordée).
/// Les échantillons consécutifs identiques sont fusionnés en sessions.
/// Conçu pour les journées fragmentées : aucun coût à changer de contexte
/// cent fois par jour, c'est même ce qu'on veut mesurer.
final class Sampler {
    static let tickInterval: TimeInterval = 5
    static let idleThreshold: TimeInterval = 180 // 3 min sans clavier/souris = absent

    /// Processus qui ne sont pas des apps mais des états « absent » : écran
    /// verrouillé, écran de connexion, économiseur. Quand ils sont au premier
    /// plan, l'utilisateur n'est pas là, on n'enregistre rien.
    static let awayBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
        "com.apple.screensaver",
    ]

    private(set) var isPaused = false {
        didSet { if isPaused { closeCurrentSession(at: Date()) } }
    }
    /// Reprise automatique programmée (pause d'une heure, jusqu'à demain...).
    private(set) var resumeDate: Date?

    /// Vrai quand l'écran est verrouillé, en veille ou sous économiseur :
    /// l'utilisateur est absent, aucun échantillon n'est pris. Détecté par les
    /// notifications système (verrouillage, veille écran, économiseur) plutôt
    /// que par l'inactivité clavier/souris, qui n'est pas fiable écran verrouillé.
    private var isAway = false

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
        // Veille de l'écran (le Mac reste éveillé mais l'écran s'éteint) :
        // willSleep ne se déclenche pas dans ce cas, il faut l'observer à part.
        center.addObserver(
            self, selector: #selector(beginAway),
            name: NSWorkspace.screensDidSleepNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(endAway),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )

        // Verrouillage de l'écran et économiseur : seules notifications
        // distribuées (non documentées mais stables de longue date) qui
        // signalent que l'utilisateur s'est absenté sans éteindre l'écran.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self, selector: #selector(beginAway),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil
        )
        distributed.addObserver(
            self, selector: #selector(endAway),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil
        )
        distributed.addObserver(
            self, selector: #selector(beginAway),
            name: NSNotification.Name("com.apple.screensaver.didstart"), object: nil
        )
        distributed.addObserver(
            self, selector: #selector(endAway),
            name: NSNotification.Name("com.apple.screensaver.didstop"), object: nil
        )
    }

    func setPaused(_ paused: Bool, until date: Date? = nil) {
        isPaused = paused
        resumeDate = paused ? date : nil
    }

    /// À appeler avant de quitter : ferme proprement la session en cours.
    func flush() {
        closeCurrentSession(at: Date())
    }

    @objc private func systemWillSleep() { closeCurrentSession(at: Date()) }
    @objc private func sessionResigned() { closeCurrentSession(at: Date()) }

    /// Écran verrouillé / en veille / économiseur : on ferme la session en
    /// cours et on suspend l'échantillonnage jusqu'au retour.
    @objc private func beginAway() {
        isAway = true
        closeCurrentSession(at: Date())
    }

    /// Retour de l'utilisateur : l'échantillonnage reprend au prochain tick.
    @objc private func endAway() { isAway = false }

    private func tick() {
        let now = Date()
        if isPaused {
            if let resumeDate, now >= resumeDate {
                setPaused(false)
                Toast.shared.show("Suivi repris")
            } else {
                return
            }
        }

        // Absent (écran verrouillé, en veille, économiseur) : rien à enregistrer.
        if isAway { return }

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
        // Filet de sécurité si une notification de verrouillage a été manquée :
        // loginwindow ou l'économiseur au premier plan = utilisateur absent.
        if let id = frontmost.bundleIdentifier, Self.awayBundleIDs.contains(id) {
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

        // Navigateur : le domaine de l'onglet actif distingue deux sites
        // ouverts dans la même app (mail vs Prospex, tous deux « Brave »).
        // Demande l'autorisation Automatisation, une fois par navigateur ;
        // sans elle, host reste vide et on retombe sur le titre de fenêtre.
        let host = Self.browserHost(for: bundle)

        if var open = current {
            if open.session.bundle == bundle && open.session.title == title
                && open.session.host == host {
                // Même contexte : on prolonge.
                open.session.end = now
                current = open
                Store.shared.updateEnd(id: open.id, end: now)
                return
            }
            closeCurrentSession(at: now)
        }

        // Nouveau contexte : on ouvre une session.
        var session = WorkSession(
            start: now, end: now, bundle: bundle, app: app, title: title, host: host
        )
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
        // Sans délai maximal, une app occupée bloquerait ce thread jusqu'à
        // 6 secondes à chaque échantillon.
        AXUIElementSetMessagingTimeout(appElement, 0.5)
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

    /// Navigateurs dont on sait lire l'URL de l'onglet actif par Apple Event.
    /// La famille Chromium partage la même syntaxe ; Safari a la sienne.
    static let browserScripts: [String: String] = [
        "com.apple.Safari": "tell application \"Safari\" to get URL of front document",
        "com.google.Chrome": "tell application \"Google Chrome\" to get URL of active tab of front window",
        "com.brave.Browser": "tell application \"Brave Browser\" to get URL of active tab of front window",
        "com.microsoft.edgemac": "tell application \"Microsoft Edge\" to get URL of active tab of front window",
        "com.vivaldi.Vivaldi": "tell application \"Vivaldi\" to get URL of active tab of front window",
        "company.thebrowser.Browser": "tell application \"Arc\" to get URL of active tab of front window",
    ]

    /// Navigateurs déjà passés par la demande d'autorisation ce lancement.
    private static var promptedBrowsers = Set<String>()

    /// Vérifie (et demande si besoin) l'autorisation d'automatiser une app.
    /// `askUserIfNeeded: true` fait apparaître la fenêtre de consentement TCC
    /// la première fois. Le simple envoi via NSAppleScript ne la déclenche
    /// pas toujours : c'est l'API dédiée qui la force de façon fiable.
    @discardableResult
    static func determineAutomationPermission(bundleID: String, askUserIfNeeded: Bool) -> OSStatus {
        guard let data = bundleID.data(using: .utf8) else {
            return OSStatus(errAEEventNotPermitted)
        }
        var target = AEAddressDesc()
        let created = data.withUnsafeBytes { raw -> OSStatus in
            AECreateDesc(typeApplicationBundleID, raw.baseAddress, data.count, &target)
        }
        guard created == noErr else { return created }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(
            &target, typeWildCard, typeWildCard, askUserIfNeeded
        )
    }

    /// Demande explicitement l'autorisation pour tous les navigateurs ouverts
    /// (appelé depuis le menu). L'app cible doit tourner pour que macOS
    /// affiche la demande.
    static func requestBrowserAutomation() {
        let running = NSWorkspace.shared.runningApplications
            .compactMap { $0.bundleIdentifier }
            .filter { browserScripts.keys.contains($0) }
        guard !running.isEmpty else {
            Toast.shared.show("Ouvre ton navigateur puis réessaie")
            return
        }
        for id in running {
            promptedBrowsers.insert(id)
            determineAutomationPermission(bundleID: id, askUserIfNeeded: true)
        }
        Toast.shared.show("Autorisation demandée. Coche Sablier dans la liste, puis c'est bon.")
    }

    /// Vrai si ce bundle est un navigateur dont on sait lire l'onglet actif.
    static func isBrowser(_ bundleID: String) -> Bool {
        browserScripts.keys.contains(bundleID)
    }

    /// Domaine de l'onglet actif d'un navigateur (ex. "mail.google.com"),
    /// ou "" si l'app n'est pas un navigateur connu, si l'autorisation
    /// Automatisation manque, ou s'il n'y a pas d'onglet ouvert. Le préfixe
    /// "www." est retiré pour que les règles n'aient pas à le prévoir.
    static func browserHost(for bundleID: String) -> String {
        guard let source = browserScripts[bundleID] else { return "" }
        // Première rencontre de ce navigateur : force la demande TCC.
        if !promptedBrowsers.contains(bundleID) {
            promptedBrowsers.insert(bundleID)
            determineAutomationPermission(bundleID: bundleID, askUserIfNeeded: true)
        }
        guard let script = NSAppleScript(source: source) else { return "" }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        guard error == nil, let urlString = output.stringValue,
              let host = URL(string: urlString)?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
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
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
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
