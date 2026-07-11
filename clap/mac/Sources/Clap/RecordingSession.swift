import Foundation

/// Données d'une session d'enregistrement, sauvegardées à côté de la vidéo
/// brute pour pouvoir ré-exporter plus tard avec d'autres réglages.
/// Les temps sont en secondes, relatifs à la première image vidéo.
struct RecordingData: Codable {
    var version = 2
    var pixelWidth: Double
    var pixelHeight: Double
    /// Durée de la vidéo brute, en secondes.
    var duration: Double

    var hasMic = false
    /// Décalage (s) entre le début du micro et la première image vidéo :
    /// positif si le micro a démarré avant la vidéo.
    var micOffset: Double = 0

    var hasWebcam = false
    /// Même convention que micOffset, pour la piste webcam.
    var webcamOffset: Double = 0

    var points: [MousePoint] = []
    var clicks: [MouseClick] = []
    var keys: [KeyEvent] = []

    /// Zooms édités dans l'éditeur ; nil = détection automatique.
    var zoomSegments: [ZoomSegment]?
    /// Rognage édité dans l'éditeur.
    var trimStart: Double = 0
    var trimEnd: Double?

    enum CodingKeys: String, CodingKey {
        case version, pixelWidth, pixelHeight, duration
        case hasMic, micOffset, hasWebcam, webcamOffset
        case points, clicks, keys, zoomSegments, trimStart, trimEnd
    }

    init(pixelWidth: Double, pixelHeight: Double, duration: Double) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
    }

    /// Décodage tolérant : les sessions v1 n'ont pas les nouveaux champs.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        pixelWidth = try c.decode(Double.self, forKey: .pixelWidth)
        pixelHeight = try c.decode(Double.self, forKey: .pixelHeight)
        duration = try c.decode(Double.self, forKey: .duration)
        hasMic = try c.decodeIfPresent(Bool.self, forKey: .hasMic) ?? false
        micOffset = try c.decodeIfPresent(Double.self, forKey: .micOffset) ?? 0
        hasWebcam = try c.decodeIfPresent(Bool.self, forKey: .hasWebcam) ?? false
        webcamOffset = try c.decodeIfPresent(Double.self, forKey: .webcamOffset) ?? 0
        points = try c.decodeIfPresent([MousePoint].self, forKey: .points) ?? []
        clicks = try c.decodeIfPresent([MouseClick].self, forKey: .clicks) ?? []
        keys = try c.decodeIfPresent([KeyEvent].self, forKey: .keys) ?? []
        zoomSegments = try c.decodeIfPresent([ZoomSegment].self, forKey: .zoomSegments)
        trimStart = try c.decodeIfPresent(Double.self, forKey: .trimStart) ?? 0
        trimEnd = try c.decodeIfPresent(Double.self, forKey: .trimEnd)
    }

    /// Les zooms effectifs : édités s'ils existent, sinon auto-détectés.
    var effectiveZoomSegments: [ZoomSegment] {
        zoomSegments ?? ZoomSegment.autoDetect(clicks: clicks, duration: duration)
    }

    var effectiveTrimEnd: Double { trimEnd ?? duration }
}

struct RecordingSession {
    let directory: URL

    var rawVideoURL: URL { directory.appendingPathComponent("raw.mov") }
    var micURL: URL { directory.appendingPathComponent("mic.m4a") }
    var webcamURL: URL { directory.appendingPathComponent("webcam.mov") }
    var dataURL: URL { directory.appendingPathComponent("session.json") }

    static var recordingsRoot: URL {
        FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clap", isDirectory: true)
    }

    static func create() throws -> RecordingSession {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let dir = recordingsRoot.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return RecordingSession(directory: dir)
    }

    /// La session la plus récente qui possède un session.json (pour
    /// « Rouvrir le dernier enregistrement »).
    static func latest() -> RecordingSession? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: recordingsRoot, includingPropertiesForKeys: nil
        ) else { return nil }
        let candidates = entries
            .filter { fm.fileExists(atPath: $0.appendingPathComponent("session.json").path) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        return candidates.first.map { RecordingSession(directory: $0) }
    }

    func save(_ data: RecordingData) throws {
        let encoder = JSONEncoder()
        try encoder.encode(data).write(to: dataURL)
    }

    func load() throws -> RecordingData {
        try JSONDecoder().decode(RecordingData.self, from: Data(contentsOf: dataURL))
    }
}
