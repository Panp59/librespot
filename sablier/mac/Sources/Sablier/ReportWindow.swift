import AppKit

// MARK: - Données d'une journée

struct DayReport {
    var day: Date
    var sessions: [WorkSession] = []
    var categories: [(name: String, duration: TimeInterval)] = []
    var apps: [(name: String, duration: TimeInterval)] = []
    var total: TimeInterval = 0
    var contextSwitches = 0
    var longestFocus: TimeInterval = 0
    var longestFocusApp = ""
    var rules: [CategoryRule] = []

    static func build(day: Date) -> DayReport {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        var report = DayReport(day: start)
        report.rules = Categorizer.loadRules()
        report.sessions = Store.shared.sessions(from: start, to: end)
            .filter { $0.duration > 0 }
        report.total = report.sessions.reduce(0) { $0 + $1.duration }

        var byCategory: [String: TimeInterval] = [:]
        var byApp: [String: TimeInterval] = [:]
        for session in report.sessions {
            let category = Categorizer.category(for: session, rules: report.rules)
            byCategory[category, default: 0] += session.duration
            byApp[session.app, default: 0] += session.duration
        }
        report.categories = byCategory.sorted { $0.value > $1.value }
            .map { (name: $0.key, duration: $0.value) }
        report.apps = byApp.sorted { $0.value > $1.value }
            .map { (name: $0.key, duration: $0.value) }

        // Fragmentation : on fusionne les sessions consécutives de la même
        // app (un changement d'onglet n'est pas un changement de contexte),
        // puis on compte les bascules entre blocs.
        var blocks: [(app: String, start: Date, end: Date)] = []
        for session in report.sessions {
            if var last = blocks.last,
               last.app == session.app,
               session.start.timeIntervalSince(last.end) < 30 {
                last.end = max(last.end, session.end)
                blocks[blocks.count - 1] = last
            } else {
                blocks.append((session.app, session.start, session.end))
            }
        }
        report.contextSwitches = max(0, blocks.count - 1)
        if let longest = blocks.max(by: {
            $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start)
        }) {
            report.longestFocus = longest.end.timeIntervalSince(longest.start)
            report.longestFocusApp = longest.app
        }
        return report
    }
}

// MARK: - Frise chronologique de la journée

final class TimelineView: NSView {
    var sessions: [WorkSession] = []
    var rules: [CategoryRule] = []
    var onHover: ((String) -> Void)?

    private var range: (start: Date, end: Date)? {
        guard let first = sessions.first, let last = sessions.last else { return nil }
        return (first.start, last.end)
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.5, alpha: 0.12).setFill()
        let band = bandRect
        NSBezierPath(roundedRect: band, xRadius: 6, yRadius: 6).fill()

        guard let range, range.end > range.start else {
            let text = "Aucune activité enregistrée ce jour."
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: band.midX - size.width / 2, y: band.midY - size.height / 2),
                withAttributes: attributes
            )
            return
        }

        let span = range.end.timeIntervalSince(range.start)
        func x(_ date: Date) -> CGFloat {
            band.minX + band.width * CGFloat(date.timeIntervalSince(range.start) / span)
        }

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(roundedRect: band, xRadius: 6, yRadius: 6).addClip()
        for session in sessions {
            let category = Categorizer.category(for: session, rules: rules)
            Categorizer.color(for: category).setFill()
            let rect = NSRect(
                x: x(session.start),
                y: band.minY,
                width: max(1, x(session.end) - x(session.start)),
                height: band.height
            )
            rect.fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        // Graduations horaires.
        let calendar = Calendar.current
        var tick = calendar.dateInterval(of: .hour, for: range.start)?.end ?? range.start
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let formatter = DateFormatter()
        formatter.dateFormat = "H'h'"
        while tick < range.end {
            let tx = x(tick)
            NSColor.tertiaryLabelColor.withAlphaComponent(0.4).setFill()
            NSRect(x: tx, y: band.minY - 4, width: 1, height: 4).fill()
            let label = formatter.string(from: tick)
            label.draw(at: NSPoint(x: tx - 6, y: 0), withAttributes: attributes)
            tick = tick.addingTimeInterval(3600)
        }
    }

    private var bandRect: NSRect {
        NSRect(x: 0, y: 18, width: bounds.width, height: bounds.height - 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let range, range.end > range.start else { return }
        let point = convert(event.locationInWindow, from: nil)
        let band = bandRect
        guard band.contains(point) else {
            onHover?("")
            return
        }
        let span = range.end.timeIntervalSince(range.start)
        let date = range.start.addingTimeInterval(
            span * Double((point.x - band.minX) / band.width)
        )
        guard let session = sessions.first(where: { $0.start <= date && date <= $0.end }) else {
            onHover?("")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let category = Categorizer.category(for: session, rules: rules)
        var text = "\(formatter.string(from: session.start)) à "
            + "\(formatter.string(from: session.end))  \(session.app)"
        if !session.title.isEmpty {
            text += "  «\u{202F}\(session.title)\u{202F}»"
        }
        text += "  (\(category), \(formatDuration(session.duration)))"
        onHover?(text)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?("")
    }
}

// MARK: - Barres horizontales (catégories, apps)

final class BarsView: NSView {
    var rows: [(label: String, duration: TimeInterval, color: NSColor)] = [] {
        didSet {
            heightConstraint?.constant = CGFloat(rows.count) * Self.rowHeight
            needsDisplay = true
        }
    }
    var heightConstraint: NSLayoutConstraint?
    static let rowHeight: CGFloat = 26

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let maxDuration = rows.map(\.duration).max(), maxDuration > 0 else { return }
        let labelWidth: CGFloat = 170
        let durationWidth: CGFloat = 70
        let barArea = bounds.width - labelWidth - durationWidth - 16

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
        ]
        let durationAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        for (index, row) in rows.enumerated() {
            let y = CGFloat(index) * Self.rowHeight
            row.color.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 0, y: y + 7, width: 10, height: 10),
                xRadius: 3, yRadius: 3
            ).fill()

            let label = row.label as NSString
            label.draw(
                in: NSRect(x: 18, y: y + 4, width: labelWidth - 18, height: 18),
                withAttributes: labelAttributes
            )

            let width = max(2, barArea * CGFloat(row.duration / maxDuration))
            row.color.withAlphaComponent(0.85).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: labelWidth, y: y + 6, width: width, height: 12),
                xRadius: 4, yRadius: 4
            ).fill()

            (formatDuration(row.duration) as NSString).draw(
                at: NSPoint(x: labelWidth + width + 8, y: y + 4),
                withAttributes: durationAttributes
            )
        }
    }
}

// MARK: - Vue semaine (colonnes empilées)

final class WeekView: NSView {
    struct Day {
        var label: String
        var total: TimeInterval
        var stacks: [(duration: TimeInterval, color: NSColor)]
        var isSelected: Bool
    }
    var days: [Day] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard !days.isEmpty else { return }
        let maxTotal = max(days.map(\.total).max() ?? 1, 1)
        let columnWidth = bounds.width / CGFloat(days.count)
        let chartBottom: CGFloat = 20
        let chartHeight = bounds.height - chartBottom - 18

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let totalAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        for (index, day) in days.enumerated() {
            let centerX = columnWidth * (CGFloat(index) + 0.5)
            let barWidth = min(34, columnWidth * 0.5)
            var y = chartBottom
            for stack in day.stacks {
                let height = chartHeight * CGFloat(stack.duration / maxTotal)
                stack.color.setFill()
                NSRect(
                    x: centerX - barWidth / 2, y: y,
                    width: barWidth, height: max(height, stack.duration > 0 ? 1 : 0)
                ).fill()
                y += height
            }
            if day.isSelected {
                NSColor.controlAccentColor.setStroke()
                let outline = NSBezierPath(rect: NSRect(
                    x: centerX - barWidth / 2 - 3, y: chartBottom - 3,
                    width: barWidth + 6, height: max(y - chartBottom, 2) + 6
                ))
                outline.lineWidth = 1.5
                outline.stroke()
            }

            let label = day.label as NSString
            let labelSize = label.size(withAttributes: labelAttributes)
            label.draw(
                at: NSPoint(x: centerX - labelSize.width / 2, y: 4),
                withAttributes: labelAttributes
            )
            if day.total > 0 {
                let total = formatDuration(day.total) as NSString
                let totalSize = total.size(withAttributes: totalAttributes)
                total.draw(
                    at: NSPoint(x: centerX - totalSize.width / 2, y: min(y + 3, bounds.height - 14)),
                    withAttributes: totalAttributes
                )
            }
        }
    }
}

// MARK: - Fenêtre de rapport

final class ReportWindowController: NSObject, NSWindowDelegate {
    static let shared = ReportWindowController()

    private var window: NSWindow?
    private var displayedDay = Date()

    private let dateLabel = NSTextField(labelWithString: "")
    private let statsLabel = NSTextField(labelWithString: "")
    private let timeline = TimelineView()
    private let hoverLabel = NSTextField(labelWithString: " ")
    private let categoryBars = BarsView()
    private let appBars = BarsView()
    private let weekView = WeekView()
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private var summaryButton: NSButton?

    func show() {
        if window == nil {
            buildWindow()
        }
        displayedDay = Date()
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        reload()
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sablier"
        window.minSize = NSSize(width: 780, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        // En-tête : navigation de date + actions.
        let previousButton = NSButton(title: "‹", target: self, action: #selector(previousDay))
        let nextButton = NSButton(title: "›", target: self, action: #selector(nextDay))
        let todayButton = NSButton(title: "Aujourd'hui", target: self, action: #selector(goToday))
        dateLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let rulesButton = NSButton(title: "Règles...", target: self, action: #selector(openRules))
        rulesButton.toolTip = "Modifier les règles de catégorisation (fichier texte)"
        let csvButton = NSButton(title: "Exporter CSV", target: self, action: #selector(exportCSV))
        let aiButton = NSButton(title: "Bilan IA", target: self, action: #selector(generateSummary))
        aiButton.toolTip = "Résumé de la journée par le LLM local (Ollama)"
        summaryButton = aiButton

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [
            previousButton, dateLabel, nextButton, todayButton, headerSpacer,
            rulesButton, csvButton, aiButton,
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        statsLabel.font = .systemFont(ofSize: 12)
        statsLabel.textColor = .secondaryLabelColor

        hoverLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        hoverLabel.textColor = .secondaryLabelColor
        hoverLabel.lineBreakMode = .byTruncatingTail
        timeline.onHover = { [weak self] text in
            self?.hoverLabel.stringValue = text.isEmpty ? " " : text
        }

        summaryLabel.font = .systemFont(ofSize: 13)
        summaryLabel.isSelectable = true

        let stack = NSStackView(views: [
            header,
            statsLabel,
            timeline,
            hoverLabel,
            sectionTitle("Par catégorie"),
            categoryBars,
            sectionTitle("Top applications"),
            appBars,
            sectionTitle("La semaine"),
            weekView,
            summaryLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 24, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = stack
        window.contentView = scroll

        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clip.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            stack.widthAnchor.constraint(equalTo: clip.widthAnchor),
        ])

        // Largeurs pleines pour les vues dessinées.
        for view in [timeline, categoryBars, appBars, weekView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        timeline.heightAnchor.constraint(equalToConstant: 72).isActive = true
        weekView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        categoryBars.heightConstraint = categoryBars.heightAnchor.constraint(equalToConstant: 10)
        categoryBars.heightConstraint?.isActive = true
        appBars.heightConstraint = appBars.heightAnchor.constraint(equalToConstant: 10)
        appBars.heightConstraint?.isActive = true
        hoverLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        summaryLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
    }

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        return label
    }

    // MARK: chargement

    private func reload() {
        let report = DayReport.build(day: displayedDay)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        dateLabel.stringValue = formatter.string(from: report.day).capitalized

        if report.total > 0 {
            var stats = "Temps actif : \(formatDuration(report.total))"
            stats += "    Changements de contexte : \(report.contextSwitches)"
            if report.longestFocus > 0 {
                stats += "    Plus longue concentration : "
                    + "\(formatDuration(report.longestFocus)) (\(report.longestFocusApp))"
            }
            if !Sampler.accessibilityGranted {
                stats += "    (titres de fenêtres désactivés : autorisation Accessibilité absente)"
            }
            statsLabel.stringValue = stats
        } else {
            statsLabel.stringValue = "Aucune activité enregistrée ce jour."
        }

        timeline.sessions = report.sessions
        timeline.rules = report.rules
        timeline.needsDisplay = true

        categoryBars.rows = report.categories.map {
            (label: $0.name, duration: $0.duration, color: Categorizer.color(for: $0.name))
        }
        appBars.rows = report.apps.prefix(8).map {
            (label: $0.name, duration: $0.duration, color: NSColor.controlAccentColor)
        }

        reloadWeek(reference: report.day, rules: report.rules)
        summaryLabel.stringValue = ""
    }

    private func reloadWeek(reference: Date, rules: [CategoryRule]) {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE d"

        var days: [WeekView.Day] = []
        for offset in stride(from: -6, through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: reference) else { continue }
            let start = calendar.startOfDay(for: day)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let sessions = Store.shared.sessions(from: start, to: end)
            var byCategory: [String: TimeInterval] = [:]
            for session in sessions {
                byCategory[Categorizer.category(for: session, rules: rules), default: 0]
                    += session.duration
            }
            let stacks = byCategory.sorted { $0.value > $1.value }.map {
                (duration: $0.value, color: Categorizer.color(for: $0.key))
            }
            days.append(WeekView.Day(
                label: formatter.string(from: day),
                total: byCategory.values.reduce(0, +),
                stacks: stacks,
                isSelected: offset == 0
            ))
        }
        weekView.days = days
    }

    // MARK: actions

    @objc private func previousDay() { shiftDay(-1) }
    @objc private func nextDay() { shiftDay(1) }

    private func shiftDay(_ delta: Int) {
        if let day = Calendar.current.date(byAdding: .day, value: delta, to: displayedDay) {
            displayedDay = min(day, Date())
            reload()
        }
    }

    @objc private func goToday() {
        displayedDay = Date()
        reload()
    }

    @objc private func openRules() {
        Categorizer.ensureRulesFile()
        NSWorkspace.shared.open(Categorizer.rulesFileURL)
        Toast.shared.show("Modifie, enregistre, puis reviens : tout se reclasse")
    }

    @objc private func exportCSV() {
        let report = DayReport.build(day: displayedDay)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var csv = "debut;fin;duree_s;application;titre;categorie\n"
        for session in report.sessions {
            let category = Categorizer.category(for: session, rules: report.rules)
            let title = session.title.replacingOccurrences(of: ";", with: ",")
            csv += "\(formatter.string(from: session.start));"
                + "\(formatter.string(from: session.end));"
                + "\(Int(session.duration));"
                + "\(session.app);\(title);\(category)\n"
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sablier-\(dayFormatter.string(from: displayedDay)).csv"
        guard let window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                Toast.shared.show("Export CSV enregistré")
            } catch {
                Toast.shared.show("Échec de l'export : \(error.localizedDescription)")
            }
        }
    }

    @objc private func generateSummary() {
        let report = DayReport.build(day: displayedDay)
        guard report.total > 0 else {
            Toast.shared.show("Rien à résumer ce jour")
            return
        }
        var lines = ["Total actif : \(formatDuration(report.total)), "
            + "\(report.contextSwitches) changements de contexte, "
            + "plus longue concentration \(formatDuration(report.longestFocus)) "
            + "(\(report.longestFocusApp))."]
        lines.append("Par catégorie :")
        for entry in report.categories {
            lines.append("- \(entry.name) : \(formatDuration(entry.duration))")
        }
        lines.append("Par application :")
        for entry in report.apps.prefix(10) {
            lines.append("- \(entry.name) : \(formatDuration(entry.duration))")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"

        summaryButton?.isEnabled = false
        summaryButton?.title = "Génération..."
        summaryLabel.stringValue = ""
        SummaryClient.summarize(
            day: formatter.string(from: report.day),
            lines: lines
        ) { [weak self] result in
            self?.summaryButton?.isEnabled = true
            self?.summaryButton?.title = "Bilan IA"
            switch result {
            case .success(let text):
                self?.summaryLabel.stringValue = "Bilan (\(SummaryClient.model)) : \(text)"
            case .failure:
                Toast.shared.show("Ollama injoignable : lance-le puis réessaie")
            }
        }
    }
}
