import Foundation

/// Une fenêtre temporelle pendant laquelle la caméra virtuelle zoome.
/// Détectés automatiquement à partir des clics, puis modifiables dans
/// l'éditeur (désactivation, suppression, ajout manuel).
struct ZoomSegment: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    var enabled = true

    /// Détection automatique : une fenêtre par clic, fusionnées quand elles
    /// se chevauchent ou presque.
    static func autoDetect(clicks: [MouseClick], duration: Double) -> [ZoomSegment] {
        let holdBefore = 0.25
        let holdAfter = 1.4
        let mergeGap = 1.2

        let windows = clicks
            .map { (start: max(0, $0.t - holdBefore), end: min(duration, $0.t + holdAfter)) }
            .sorted { $0.start < $1.start }

        var merged: [(start: Double, end: Double)] = []
        for window in windows {
            if var last = merged.last, window.start - last.end < mergeGap {
                last.end = max(last.end, window.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(window)
            }
        }
        return merged.map { ZoomSegment(start: $0.start, end: $0.end) }
    }
}

/// Une touche (ou raccourci) enregistrée pendant la capture, déjà mise en
/// forme pour l'affichage (ex. « ⌘⇧P », « A », « ␣ »).
struct KeyEvent: Codable {
    var t: Double
    var text: String
    /// Vrai si l'événement contient des modificateurs (raccourci) : il est
    /// alors affiché seul, sinon les lettres tapées sont regroupées en mot.
    var isShortcut: Bool
}
