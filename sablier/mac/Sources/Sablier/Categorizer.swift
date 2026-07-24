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
    # du bundle, le nom de l'app, le DOMAINE du site (navigateurs) et le
    # titre de la fenêtre.
    # La PREMIÈRE règle qui correspond gagne : mettez les plus précises en haut.
    # Modifiez, enregistrez, rouvrez le rapport : tout l'historique se reclasse.

    # Sites web (le domaine de l'onglet actif, tout tourne dans le navigateur).
    # C'est ici que se distinguent deux sites ouverts dans le même navigateur.
    prospex => Prospex
    mail.google.com => Mails
    outlook.office => Mails
    calendar.google => Réunions
    meet.google => Réunions
    github.com => Dev
    chatgpt.com => IA
    claude.ai => IA

    # Titres de fenêtres et documents (précis, donc en premier)
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

    # Navigation web : repli quand le domaine n'a pas de règle plus précise
    # au-dessus. Ces motifs matchent le nom de l'app, donc à garder EN BAS.
    safari => Web
    chrome => Web
    brave => Web
    edge => Web
    firefox => Web
    vivaldi => Web
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

    /// Réécrit le fichier avec les règles par défaut de cette version.
    /// (ensureRulesFile ne touche jamais un fichier existant : après une
    /// mise à jour de Sablier, les nouvelles règles par défaut ne
    /// s'appliquent qu'ici.)
    static func restoreDefaultRules() {
        try? defaultRulesText.write(to: rulesFileURL, atomically: true, encoding: .utf8)
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

    /// Ajoute une règle `motif => catégorie`. Insérée AVANT les règles
    /// existantes pour gagner au premier match (une règle par domaine doit
    /// passer devant le repli par nom d'app comme `brave => Web`).
    static func addRule(pattern: String, category: String) {
        ensureRulesFile()
        let url = rulesFileURL
        var lines = (try? String(contentsOf: url, encoding: .utf8))?
            .components(separatedBy: "\n") ?? []
        let rule = "\(pattern) => \(category)"

        func isRuleLine(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("#") && trimmed.contains("=>")
        }
        if let first = lines.firstIndex(where: isRuleLine) {
            lines.insert(rule, at: first)
        } else {
            lines.append(rule)
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func category(for session: WorkSession, rules: [CategoryRule]) -> String {
        let haystack = "\(session.bundle) \(session.app) \(session.host) \(session.title)"
            .lowercased()
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
