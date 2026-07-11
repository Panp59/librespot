import AppKit

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

/// Enregistre la trajectoire de la souris (60 Hz) et les clics pendant la
/// capture d'écran. Le curseur réel est masqué dans la vidéo : ces données
/// servent à redessiner un curseur synthétique lissé au rendu.
final class MouseTracker {
    private var timer: Timer?
    private var monitors: [Any] = []
    private(set) var points: [MousePoint] = []
    private(set) var clicks: [MouseClick] = []

    private let screenFrame: NSRect
    private let scale: CGFloat

    init(screen: NSScreen) {
        screenFrame = screen.frame
        scale = screen.backingScaleFactor
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
        let (x, y) = pixelPosition()
        points.append(MousePoint(t: CACurrentMediaTime(), x: x, y: y))
    }

    private func recordClick() {
        let (x, y) = pixelPosition()
        clicks.append(MouseClick(t: CACurrentMediaTime(), x: x, y: y))
    }

    /// NSEvent.mouseLocation est en points, origine en bas à gauche de
    /// l'écran ; la vidéo est en pixels, origine en haut à gauche.
    private func pixelPosition() -> (Double, Double) {
        let location = NSEvent.mouseLocation
        let x = (location.x - screenFrame.minX) * scale
        let y = (screenFrame.maxY - location.y) * scale
        return (Double(x), Double(y))
    }
}
