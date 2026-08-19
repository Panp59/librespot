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
    /// Décalages des pistes et notes prises pendant la réunion, relus depuis
    /// meta.json : sans eux, une retranscription désaligne les interlocuteurs
    /// d'une réunion Teams et perd les notes qui guident le compte-rendu.
    let micOffset: Double
    let systemOffset: Double
    let notes: String

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
    static let metaFileName = "meta.json"

    /// Format de date des dossiers, côté app comme côté backend.
    /// Locale POSIX obligatoire : sous un calendrier régional non grégorien,
    /// "yyyy" produirait une autre année et les noms deviendraient illisibles.
    static func folderDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter
    }

    /// Mémorise le dossier de sortie produit par le backend.
    static func writeOutputLink(_ outputDir: String, in directory: URL) {
        try? outputDir.write(
            to: directory.appendingPathComponent(linkFileName),
            atomically: true, encoding: .utf8
        )
    }

    /// Conserve ce qui serait perdu à la retranscription : le calage des
    /// pistes et les notes prises pendant la réunion.
    static func writeMeta(
        micOffset: Double, systemOffset: Double, notes: String, in directory: URL
    ) {
        let meta: [String: Any] = [
            "mic_offset": micOffset,
            "system_offset": systemOffset,
            "notes": notes,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: meta) else { return }
        try? data.write(to: directory.appendingPathComponent(metaFileName))
    }

    /// Dossier des transcriptions produites par le backend.
    /// (MURMURE_OUTPUT_DIR côté Python, ~/Documents/Murmure par défaut.)
    static var outputRoot: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmure/Réunions", isDirectory: true)
    }

    /// Retrouve une transcription existante pour un enregistrement nommé
    /// "yyyy-MM-dd HHmm". Attention : le backend date ses dossiers de sortie
    /// de la FIN de la transcription, pas du début de l'enregistrement. On
    /// cherche donc la première sortie postérieure au début (dans les 24 h),
    /// et non un préfixe identique. Utile pour les réunions transcrites avant
    /// l'introduction du fichier de lien.
    private static func findExistingOutput(matching folderName: String) -> URL? {
        let fm = FileManager.default
        let parser = folderDateFormatter()
        guard let start = parser.date(from: folderName),
              let entries = try? fm.contentsOfDirectory(
                  at: outputRoot,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              )
        else { return nil }

        return entries.compactMap { url -> (URL, Date)? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { return nil }
            let name = url.lastPathComponent
            guard name.count >= 15,
                  let date = parser.date(from: String(name.prefix(15))),
                  date >= start,
                  date.timeIntervalSince(start) < 86_400
            else { return nil }
            return (url, date)
        }
        .min { $0.1 < $1.1 }?.0
    }

    /// Tous les enregistrements, du plus récent au plus ancien.
    static func all(in root: URL) -> [MeetingRecording] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let formatter = folderDateFormatter()

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

            // Calage des pistes et notes, si l'enregistrement les a conservés.
            var micOffset = 0.0
            var systemOffset = 0.0
            var notes = ""
            if let data = try? Data(contentsOf: entry.appendingPathComponent(metaFileName)),
               let meta = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                micOffset = meta["mic_offset"] as? Double ?? 0
                systemOffset = meta["system_offset"] as? Double ?? 0
                notes = meta["notes"] as? String ?? ""
            }

            result.append(MeetingRecording(
                directory: entry, date: date,
                hasMic: hasMic, hasSystem: hasSystem, outputDir: outputDir,
                micOffset: micOffset, systemOffset: systemOffset, notes: notes
            ))
        }
        return result.sorted { $0.date > $1.date }
    }
}
