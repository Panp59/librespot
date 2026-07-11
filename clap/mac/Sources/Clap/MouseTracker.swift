import AppKit
import QuartzCore

/// Un échantillon de position de la souris, en pixels vidéo (origine en haut
/// à gauche). `t` est en secondes, horloge hôte absolue pendant la capture,
/// puis relative au début de la vidéo une fois la session sauvegardée.
struct MousePoint: Codable {
    var t: Double
    var x: Double
    var y: Double
}

struct MouseClick: Codable {
    var t: Double
    var x: Double
    var y: Double
}

/// Zone capturée : l'écran entier, ou une fenêtre (suivie en direct si
/// elle bouge pendant l'enregistrement).
enum CaptureArea {
    case display(screen: NSScreen)
    case window(windowID: CGWindowID, scale: CGFloat)
}

/// Enregistre la trajectoire de la souris (60 Hz) et les clics pendant la
/// capture. Le curseur réel est masqué dans la vidéo : ces données servent
/// à redessiner un curseur synthétique lissé au rendu.
final class MouseTracker {
    private var timer: Timer?
    private var monitors: [Any] = []
    private(set) var points: [MousePoint] = []
    private(set) var clicks: [MouseClick] = []

    private let area: CaptureArea
    private var lastWindowBounds: CGRect?

    init(area: CaptureArea) {
        self.area = area
    }

    func start() {
        points = []
        clicks = []

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.samplePosition()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let clickTypes: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clickTypes, handler: { [weak self] _ in
            self?.recordClick()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clickTypes, handler: { [weak self] event in
            self?.recordClick()
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
    }

    private func samplePosition() {
        guard let (x, y) = pixelPosition() else { return }
        points.append(MousePoint(t: CACurrentMediaTime(), x: x, y: y))
    }

    private func recordClick() {
        guard let (x, y) = pixelPosition() else { return }
        clicks.append(MouseClick(t: CACurrentMediaTime(), x: x, y: y))
    }

    /// Position de la souris en pixels de la zone capturée, origine en haut
    /// à gauche. NSEvent.mouseLocation est en points, origine en bas à
    /// gauche de l'écran principal.
    private func pixelPosition() -> (Double, Double)? {
        let location = NSEvent.mouseLocation

        switch area {
        case .display(let screen):
            let frame = screen.frame
            let scale = screen.backingScaleFactor
            let x = (location.x - frame.minX) * scale
            let y = (frame.maxY - location.y) * scale
            return (Double(x), Double(y))

        case .window(let windowID, let scale):
            guard let bounds = currentWindowBounds(windowID) else { return nil }
            // Les bounds CGWindow sont en points, origine en HAUT à gauche
            // de l'écran principal : on convertit la souris dans ce repère.
            let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
            let topLeftX = location.x
            let topLeftY = primaryHeight - location.y
            let x = (topLeftX - bounds.minX) * scale
            let y = (topLeftY - bounds.minY) * scale
            return (Double(x), Double(y))
        }
    }

    /// Cadre actuel de la fenêtre suivie (elle peut bouger pendant
    /// l'enregistrement).
    private func currentWindowBounds(_ windowID: CGWindowID) -> CGRect? {
        if let info = CGWindowListCreateDescriptionFromArray([NSNumber(value: windowID)] as CFArray) as? [[String: Any]],
           let boundsDict = info.first?[kCGWindowBounds as String] as? NSDictionary,
           let bounds = CGRect(dictionaryRepresentation: boundsDict) {
            lastWindowBounds = bounds
            return bounds
        }
        return lastWindowBounds
    }
}
