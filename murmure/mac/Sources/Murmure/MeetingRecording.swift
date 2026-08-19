import AppKit

/// Un enregistrement de réunion sur disque, avec l'état de sa transcription.
///
/// L'audio vit dans ~/Documents/Murmure/Enregistrements/<horodatage>/ ;
/// la transcription, elle, est écrite par le backend ailleurs. Pour relier
/// les deux, Murmure dépose un fichier `sortie.txt` dans le dossier
/// d'enregistrement, contenant le chemin du dossier de sortie.
struct MeetingRecording {
    let directory: URL
    let date: Date
    let hasMic: Bool
    let hasSystem: Bool
    /// Dossier de sortie de la transcription, si elle a déjà eu lieu.
    let outputDir: URL?

    /// Réunion Teams/visio : une piste système en plus du micro.
    var mode: String { hasSystem ? "remote" : "in_person" }

    var micURL: URL? {
        hasMic ? directory.appendingPathComponent("mic.wav") : nil
    }
    var systemURL: URL? {
        hasSystem ? directory.appendingPathComponent("system.caf") : nil
    }

    var isTranscribed: Bool {
        guard let outputDir else { return false }
        return FileManager.default.fileExists(atPath: outputDir.path)
    }

    /// Le fichier à ouvrir : le compte-rendu s'il existe, sinon la
    /// transcription complète.
    var documentToOpen: URL? {
        guard let outputDir else { return nil }
        let summary = outputDir.appendingPathComponent("compte-rendu.md")
        if FileManager.default.fileExists(atPath: summary.path) { return summary }
        let transcript = outputDir.appendingPathComponent("transcription.md")
        return FileManager.default.fileExists(atPath: transcript.path) ? transcript : nil
    }

    /// Poids de l'audio, pour se repérer dans la liste.
    var sizeBytes: Int64 {
        var total: Int64 = 0
        for url in [micURL, systemURL].compactMap({ $0 }) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    static let linkFileName = "sortie.txt"

    /// Mémorise le dossier de sortie produit par le backend.
    static func writeOutputLink(_ outputDir: String, in directory: URL) {
        try? outputDir.write(
            to: directory.appendingPathComponent(linkFileName),
            atomically: true, encoding: .utf8
        )
    }

    /// Dossier des transcriptions produites par le backend.
    /// (MURMURE_OUTPUT_DIR côté Python, ~/Documents/Murmure par défaut.)
    static var outputRoot: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmure/Réunions", isDirectory: true)
    }

    /// Retrouve une transcription existante pour un enregistrement nommé
    /// "yyyy-MM-dd HHmm" : le backend nomme ses dossiers de sortie
    /// "yyyy-MM-dd HHmm <titre>", donc le préfixe suffit. Utile pour les
    /// réunions transcrites avant l'introduction du fichier de lien.
    private static func findExistingOutput(matching folderName: String) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: outputRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        return entries.first { $0.lastPathComponent.hasPrefix(folderName) }
    }

    /// Tous les enregistrements, du plus récent au plus ancien.
    static func all(in root: URL) -> [MeetingRecording] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"

        var result: [MeetingRecording] = []
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let hasMic = fm.fileExists(atPath: entry.appendingPathComponent("mic.wav").path)
            let hasSystem = fm.fileExists(atPath: entry.appendingPathComponent("system.caf").path)
            guard hasMic || hasSystem else { continue }

            // La date vient du nom du dossier ; à défaut, de sa création.
            let date = formatter.date(from: entry.lastPathComponent)
                ?? (try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                ?? Date.distantPast

            var outputDir: URL?
            let link = entry.appendingPathComponent(linkFileName)
            if let path = try? String(contentsOf: link, encoding: .utf8) {
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { outputDir = URL(fileURLWithPath: trimmed) }
            }
            // Repli pour les réunions transcrites avant l'existence du
            // fichier de lien : on cherche une sortie datée de la même minute.
            if outputDir == nil {
                outputDir = findExistingOutput(matching: entry.lastPathComponent)
            }

            result.append(MeetingRecording(
                directory: entry, date: date,
                hasMic: hasMic, hasSystem: hasSystem, outputDir: outputDir
            ))
        }
        return result.sorted { $0.date > $1.date }
    }
}
