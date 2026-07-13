import AppKit

/// Catégorisation par règles, stockées dans un simple fichier texte :
///   motif => Catégorie
/// Le motif est cherché (sans casse) dans l'identifiant du bundle, le nom
/// de l'app et le titre de la fenêtre. Première règle qui matche gagne.
/// Les règles sont relues à chaque rafraîchissement du rapport : les
/// modifier reclasse TOUT l'historique, rien n'est figé.
struct CategoryRule {
    let pattern: String
    let category: String
}

enum Categorizer {
    static let defaultCategory = "Autre"

    static var rulesFileURL: URL {
        Store.dataDirectory.appendingPathComponent("regles.txt")
    }

    static let defaultRulesText = """
    # Règles de catégorisation Sablier
    # Format : motif => Catégorie
    # Le motif est cherché (sans distinction de casse) dans l'identifiant
    # du bundle, le nom de l'app et le titre de la fenêtre.
    # La PREMIÈRE règle qui correspond gagne : mettez les plus précises en haut.
    # Modifiez, enregistrez, rouvrez le rapport : tout l'historique se reclasse.

    # Titres de fenêtres (précis, donc en premier)
    gmao => OPTIMa
    optima => OPTIMa
    devis => Commercial
    facture => Administratif

    # Réunions et démos
    teams => Réunions
    zoom.us => Réunions
    facetime => Réunions
    webex => Réunions

    # Communication
    mail => Mails
    outlook => Mails
    spark => Mails
    slack => Messages
    discord => Messages
    whatsapp => Messages
    com.apple.MobileSMS => Messages

    # Développement
    xcode => Dev
    terminal => Dev
    iterm => Dev
    visual studio code => Dev
    com.microsoft.VSCode => Dev
    cursor => Dev
    github => Dev

    # Navigation web
    safari => Web
    chrome => Web
    firefox => Web
    arc => Web

    # Bureautique
    word => Bureautique
    excel => Bureautique
    powerpoint => Bureautique
    pages => Bureautique
    numbers => Bureautique
    keynote => Bureautique
    preview => Bureautique
    com.apple.Preview => Bureautique
    notes => Bureautique

    # Divers
    spotify => Musique
    musique => Musique
    finder => Rangement
    raycast => Rangement
    """

    /// Crée le fichier de règles avec les valeurs par défaut si absent.
    static func ensureRulesFile() {
        let url = rulesFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? defaultRulesText.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func loadRules() -> [CategoryRule] {
        ensureRulesFile()
        guard let text = try? String(contentsOf: rulesFileURL, encoding: .utf8) else {
            return []
        }
        var rules: [CategoryRule] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let pattern = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let category = parts[1].trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty, !category.isEmpty else { continue }
            rules.append(CategoryRule(pattern: pattern, category: category))
        }
        return rules
    }

    static func category(for session: WorkSession, rules: [CategoryRule]) -> String {
        let haystack = "\(session.bundle) \(session.app) \(session.title)".lowercased()
        for rule in rules where haystack.contains(rule.pattern) {
            return rule.category
        }
        return defaultCategory
    }

    /// Couleur stable par catégorie (même couleur d'un jour et d'un
    /// lancement à l'autre : hachage déterministe, pas String.hashValue
    /// qui change à chaque exécution).
    static func color(for category: String) -> NSColor {
        if category == defaultCategory {
            return NSColor(calibratedWhite: 0.55, alpha: 1)
        }
        let palette: [NSColor] = [
            hex(0x4F46E5), hex(0x0EA5E9), hex(0x10B981), hex(0xF59E0B),
            hex(0xEF4444), hex(0xA855F7), hex(0xEC4899), hex(0x14B8A6),
            hex(0x84CC16), hex(0xF97316), hex(0x6366F1), hex(0x06B6D4),
        ]
        var hash: UInt64 = 5381
        for scalar in category.unicodeScalars {
            hash = hash &* 33 &+ UInt64(scalar.value)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
