import AppKit

/// Le rangement de barre de menus façon Bartender/Hidden Bar.
///
/// Mécanique : Régie pose deux items dans la barre, un TRAIT séparateur et
/// un CHEVRON. L'utilisateur glisse (avec Cmd) les icônes secondaires à
/// GAUCHE du trait. Au repli, le trait s'élargit à 10 000 points : tout ce
/// qui est à sa gauche déborde de la barre et macOS le masque. Le chevron,
/// lui, reste visible pour tout rouvrir d'un clic.
final class MenuBarConcealer {
    static let shared = MenuBarConcealer()

    private let separator: NSStatusItem
    private let chevron: NSStatusItem
    private static let expandedLength: CGFloat = 12
    private static let collapsedLength: CGFloat = 10000

    private(set) var isCollapsed = false {
        didSet { apply() }
    }

    private init() {
        // L'ordre de création compte pour la position initiale ; les
        // autosaveName laissent ensuite l'utilisateur réorganiser en
        // Cmd-glissant, et macOS s'en souvient.
        chevron = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        chevron.autosaveName = "regie-chevron"
        separator = NSStatusBar.system.statusItem(withLength: Self.expandedLength)
        separator.autosaveName = "regie-separateur"

        if let button = chevron.button {
            button.target = self
            button.action = #selector(chevronClicked)
            button.toolTip = "Régie : afficher ou masquer les icônes secondaires"
        }
        if let button = separator.button {
            button.image = Self.separatorImage()
            button.image?.isTemplate = true
            button.toolTip = "Régie : Cmd-glisse ici les icônes à masquer (à gauche du trait)"
        }
        apply()
    }

    /// À appeler une fois au lancement pour instancier les items.
    func install() {}

    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
    }

    @objc private func chevronClicked() {
        isCollapsed.toggle()
    }

    private func apply() {
        separator.length = isCollapsed ? Self.collapsedLength : Self.expandedLength
        if let button = chevron.button {
            let symbol = isCollapsed ? "chevron.left" : "chevron.right"
            button.image = NSImage(
                systemSymbolName: symbol,
                accessibilityDescription: isCollapsed ? "Afficher" : "Masquer"
            )
            button.image?.isTemplate = true
        }
    }

    /// Un trait vertical discret.
    private static func separatorImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 16), flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.8).setFill()
            NSRect(x: rect.midX - 0.5, y: 1, width: 1, height: rect.height - 2).fill()
            return true
        }
        return image
    }
}
