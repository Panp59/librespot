import Foundation

/// Données d'une session d'enregistrement, sauvegardées à côté de la vidéo
/// brute pour pouvoir ré-exporter plus tard avec d'autres réglages.
struct RecordingData: Codable {
    var pixelWidth: Double
    var pixelHeight: Double
    /// Durée de la vidéo brute, en secondes.
    var duration: Double
    var hasMic: Bool
    /// Décalage (s) entre le début du micro et la première image vidéo :
    /// positif si le micro a démarré avant la vidéo.
    var micOffset: Double
    /// Trajectoire souris et clics, temps relatifs à la première image vidéo.
    var points: [MousePoint]
    var clicks: [MouseClick]
}

struct RecordingSession {
    let directory: URL

    var rawVideoURL: URL { directory.appendingPathComponent("raw.mov") }
    var micURL: URL { directory.appendingPathComponent("mic.m4a") }
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
    /// « Exporter à nouveau le dernier enregistrement »).
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
