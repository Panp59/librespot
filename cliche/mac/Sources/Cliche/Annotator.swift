import AppKit

// MARK: - Modèle

enum AnnotationTool: Int, CaseIterable {
    case arrow, rect, ellipse, line, highlight, text, pixelate, badge, crop

    var label: String {
        switch self {
        case .arrow: return "Flèche"
        case .rect: return "Cadre"
        case .ellipse: return "Ellipse"
        case .line: return "Trait"
        case .highlight: return "Surligneur"
        case .text: return "Texte"
        case .pixelate: return "Pixeliser"
        case .badge: return "Badge"
        case .crop: return "Recadrer"
        }
    }
}

/// Une annotation, stockée en COORDONNÉES PIXELS de l'image (origine en bas
/// à gauche) : le rendu à l'écran et le rendu à l'export utilisent le même
/// code, donc ce qu'on voit est exactement ce qu'on exporte.
struct AnnotationShape {
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
    var text: String = ""
    var number: Int = 0

    var rect: NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

// MARK: - Utilitaires image

enum ImageUtils {
    static func hexColor(_ hex: UInt32) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Normalise une image chargée depuis un fichier pour que sa `size`
    /// (en points) soit égale à sa taille en PIXELS. Les captures Retina
    /// portent un DPI de 144 qui fausserait toutes les coordonnées sinon.
    static func normalized(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Version pixelisée de l'image entière (dessinée ensuite par zones).
    static func pixelated(_ image: NSImage, blockSize: CGFloat = 24) -> NSImage {
        let size = image.size
        let smallSize = NSSize(
            width: max(1, size.width / blockSize),
            height: max(1, size.height / blockSize)
        )
        let small = NSImage(size: smallSize, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .medium
            image.draw(in: rect)
            return true
        }
        return NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .none
            small.draw(in: rect)
            return true
        }
    }

    static let beautifyColors: (NSColor, NSColor) = (hexColor(0x4F46E5), hexColor(0xA855F7))

    /// « Joli fond » : marge + dégradé + coins arrondis + ombre portée,
    /// pour des captures présentables direct dans une doc ou un post.
    static func beautified(_ image: NSImage) -> NSImage {
        let size = image.size
        let pad = max(64, min(size.width, size.height) * 0.09)
        let outSize = NSSize(width: size.width + pad * 2, height: size.height + pad * 2)
        return NSImage(size: outSize, flipped: false) { rect in
            let gradient = NSGradient(starting: beautifyColors.0, ending: beautifyColors.1)
            gradient?.draw(in: rect, angle: 135)

            let imageRect = NSRect(x: pad, y: pad, width: size.width, height: size.height)
            let radius = max(10, pad * 0.22)
            let path = NSBezierPath(roundedRect: imageRect, xRadius: radius, yRadius: radius)

            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = pad * 0.45
            shadow.shadowOffset = NSSize(width: 0, height: -pad * 0.18)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.set()
            NSColor.white.setFill()
            path.fill()
            NSGraphicsContext.current?.restoreGraphicsState()

            NSGraphicsContext.current?.saveGraphicsState()
            path.addClip()
            image.draw(in: imageRect)
            NSGraphicsContext.current?.restoreGraphicsState()
            return true
        }
    }
}

// MARK: - Rendu des annotations (partagé écran / export)

enum ShapeRenderer {
    static func draw(_ shape: AnnotationShape, pixelatedImage: NSImage?) {
        switch shape.tool {
        case .arrow:
            drawArrow(shape)
        case .rect:
            let path = NSBezierPath(
                roundedRect: shape.rect,
                xRadius: shape.lineWidth,
                yRadius: shape.lineWidth
            )
            path.lineWidth = shape.lineWidth
            shape.color.setStroke()
            path.stroke()
        case .ellipse:
            let path = NSBezierPath(ovalIn: shape.rect)
            path.lineWidth = shape.lineWidth
            shape.color.setStroke()
            path.stroke()
        case .line:
            let path = NSBezierPath()
            path.move(to: shape.start)
            path.line(to: shape.end)
            path.lineWidth = shape.lineWidth
            path.lineCapStyle = .round
            shape.color.setStroke()
            path.stroke()
        case .highlight:
            let path = NSBezierPath()
            path.move(to: shape.start)
            path.line(to: shape.end)
            path.lineWidth = shape.lineWidth * 4.5
            path.lineCapStyle = .round
            shape.color.withAlphaComponent(0.35).setStroke()
            path.stroke()
        case .text:
            let fontSize = max(18, shape.lineWidth * 6)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: shape.color,
                .strokeColor: NSColor.black.withAlphaComponent(0.5),
                .strokeWidth: -2.0,
            ]
            NSAttributedString(string: shape.text, attributes: attributes)
                .draw(at: shape.start)
        case .pixelate:
            guard let pixelatedImage else { return }
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: shape.rect).addClip()
            pixelatedImage.draw(
                in: NSRect(origin: .zero, size: pixelatedImage.size)
            )
            NSGraphicsContext.current?.restoreGraphicsState()
        case .badge:
            let radius = max(16, shape.lineWidth * 3.5)
            let circle = NSRect(
                x: shape.start.x - radius,
                y: shape.start.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 4
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.set()
            shape.color.setFill()
            NSBezierPath(ovalIn: circle).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: radius * 1.1),
                .foregroundColor: NSColor.white,
            ]
            let label = NSAttributedString(string: "\(shape.number)", attributes: attributes)
            let textSize = label.size()
            label.draw(at: NSPoint(
                x: circle.midX - textSize.width / 2,
                y: circle.midY - textSize.height / 2
            ))
        case .crop:
            // Uniquement un aperçu pendant le glisser.
            let path = NSBezierPath(rect: shape.rect)
            path.lineWidth = shape.lineWidth
            path.setLineDash([8, 5], count: 2, phase: 0)
            NSColor.white.setStroke()
            path.stroke()
            NSColor.black.withAlphaComponent(0.25).setFill()
            path.fill()
        }
    }

    private static func drawArrow(_ shape: AnnotationShape) {
        let dx = shape.end.x - shape.start.x
        let dy = shape.end.y - shape.start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 2 else { return }
        let angle = atan2(dy, dx)
        let headLength = max(14, shape.lineWidth * 3.5)
        let headWidth = headLength * 0.7

        // Le trait s'arrête à la base de la pointe pour un rendu net.
        let baseX = shape.end.x - cos(angle) * headLength * 0.8
        let baseY = shape.end.y - sin(angle) * headLength * 0.8

        let path = NSBezierPath()
        path.move(to: shape.start)
        path.line(to: NSPoint(x: baseX, y: baseY))
        path.lineWidth = shape.lineWidth
        path.lineCapStyle = .round
        shape.color.setStroke()
        path.stroke()

        let head = NSBezierPath()
        head.move(to: shape.end)
        head.line(to: NSPoint(
            x: shape.end.x - cos(angle) * headLength - sin(angle) * headWidth / 2,
            y: shape.end.y - sin(angle) * headLength + cos(angle) * headWidth / 2
        ))
        head.line(to: NSPoint(
            x: shape.end.x - cos(angle) * headLength + sin(angle) * headWidth / 2,
            y: shape.end.y - sin(angle) * headLength - cos(angle) * headWidth / 2
        ))
        head.close()
        shape.color.setFill()
        head.fill()
    }
}

// MARK: - Canvas

final class AnnotationCanvas: NSView {
    var image: NSImage {
        didSet {
            pixelatedCache = nil
            needsDisplay = true
        }
    }
    var shapes: [AnnotationShape] = [] { didSet { needsDisplay = true } }
    var draft: AnnotationShape?
    var currentTool: AnnotationTool = .arrow
    var currentColor: NSColor = ImageUtils.hexColor(0xFF3B30)
    var currentLineWidth: CGFloat = 6
    var beautifyPreview = false { didSet { needsDisplay = true } }
    var badgeCounter = 0

    /// Appelé avant toute modification (pour l'historique d'annulation).
    var onWillMutate: (() -> Void)?
    var onCrop: ((NSRect) -> Void)?
    var onRequestText: ((CGPoint) -> Void)?

    private var pixelatedCache: NSImage?

    var pixelatedImage: NSImage {
        if let cached = pixelatedCache { return cached }
        let result = ImageUtils.pixelated(image)
        pixelatedCache = result
        return result
    }

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non implémenté") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // Rect d'affichage de l'image (aspect fit) dans la vue.
    private var imageRect: NSRect {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return bounds }
        let margin: CGFloat = 14
        let available = bounds.insetBy(dx: margin, dy: margin)
        let scale = min(available.width / size.width, available.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return NSRect(
            x: bounds.midX - w / 2,
            y: bounds.midY - h / 2,
            width: w,
            height: h
        )
    }

    private func toPixel(_ point: NSPoint) -> CGPoint {
        let rect = imageRect
        let scale = rect.width / max(image.size.width, 1)
        let x = (point.x - rect.minX) / scale
        let y = (point.y - rect.minY) / scale
        return CGPoint(
            x: min(max(x, 0), image.size.width),
            y: min(max(y, 0), image.size.height)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        if beautifyPreview {
            let gradient = NSGradient(
                starting: ImageUtils.beautifyColors.0,
                ending: ImageUtils.beautifyColors.1
            )
            gradient?.draw(in: bounds, angle: 135)
        } else {
            NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
            bounds.fill()
        }

        let rect = imageRect
        let scale = rect.width / max(image.size.width, 1)

        if !beautifyPreview {
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 12
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.set()
            NSColor.black.setFill()
            NSBezierPath(rect: rect).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        NSGraphicsContext.current?.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scale(by: scale)
        transform.concat()

        // Aperçu fidèle du « joli fond » : mêmes coins arrondis et même ombre
        // que l'export (les annotations près des bords sont rognées pareil).
        if beautifyPreview {
            let pad = max(64, min(image.size.width, image.size.height) * 0.09)
            let radius = max(10, pad * 0.22)
            let clipPath = NSBezierPath(
                roundedRect: NSRect(origin: .zero, size: image.size),
                xRadius: radius,
                yRadius: radius
            )
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 16
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.set()
            NSColor.white.setFill()
            clipPath.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            clipPath.addClip()
        }

        image.draw(in: NSRect(origin: .zero, size: image.size))
        for shape in shapes {
            ShapeRenderer.draw(shape, pixelatedImage: pixelatedImage)
        }
        if let draft {
            ShapeRenderer.draw(draft, pixelatedImage: pixelatedImage)
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: souris

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pixel = toPixel(convert(event.locationInWindow, from: nil))

        switch currentTool {
        case .text:
            onRequestText?(pixel)
        case .badge:
            onWillMutate?()
            badgeCounter += 1
            shapes.append(AnnotationShape(
                tool: .badge,
                start: pixel,
                end: pixel,
                color: currentColor,
                lineWidth: currentLineWidth,
                number: badgeCounter
            ))
        default:
            draft = AnnotationShape(
                tool: currentTool,
                start: pixel,
                end: pixel,
                color: currentColor,
                lineWidth: currentLineWidth
            )
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard draft != nil else { return }
        draft?.end = toPixel(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var shape = draft else { return }
        draft = nil
        shape.end = toPixel(convert(event.locationInWindow, from: nil))

        let significant = abs(shape.end.x - shape.start.x) > 4
            || abs(shape.end.y - shape.start.y) > 4
        guard significant else {
            needsDisplay = true
            return
        }

        if shape.tool == .crop {
            onCrop?(shape.rect)
        } else {
            onWillMutate?()
            shapes.append(shape)
        }
        needsDisplay = true
    }

    /// Sélection d'outil au clavier (1 à 9), défini par le contrôleur.
    var onToolShortcut: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Échap
            window?.performClose(nil)
            return
        }
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let chars = event.charactersIgnoringModifiers,
           chars.count == 1,
           let digit = Int(chars),
           digit >= 1, digit <= AnnotationTool.allCases.count {
            onToolShortcut?(digit - 1)
            return
        }
        super.keyDown(with: event)
    }

    func addText(_ text: String, at point: CGPoint) {
        guard !text.isEmpty else { return }
        onWillMutate?()
        shapes.append(AnnotationShape(
            tool: .text,
            start: point,
            end: point,
            color: currentColor,
            lineWidth: currentLineWidth,
            text: text
        ))
    }
}

// MARK: - Fenêtre

final class EditorWindow: NSWindow {
    weak var annotator: AnnotatorWindowController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.option),
           !event.modifierFlags.contains(.control) {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if event.modifierFlags.contains(.shift) {
                if key == "z" {
                    annotator?.redo()
                    return true
                }
                return super.performKeyEquivalent(with: event)
            }
            switch key {
            case "z":
                annotator?.undo()
                return true
            case "c":
                annotator?.copyImage()
                return true
            case "s":
                annotator?.save()
                return true
            case "w":
                performClose(nil)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Contrôleur

final class AnnotatorWindowController: NSObject, NSWindowDelegate {
    private static var active: [AnnotatorWindowController] = []

    private let fileURL: URL
    private let window: EditorWindow
    private let canvas: AnnotationCanvas
    private var beautify = false
    private var colorObservation: NSKeyValueObservation?
    private var toolsControl: NSSegmentedControl?

    // Historique : instantanés (image + annotations + compteur de badges).
    private typealias Snapshot = (NSImage, [AnnotationShape], Int)
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    static func open(fileURL: URL) {
        guard let raw = NSImage(contentsOf: fileURL) else {
            Toast.shared.show("Impossible d'ouvrir la capture")
            return
        }
        let controller = AnnotatorWindowController(
            fileURL: fileURL,
            image: ImageUtils.normalized(raw)
        )
        active.append(controller)
        controller.show()
    }

    private init(fileURL: URL, image: NSImage) {
        self.fileURL = fileURL
        canvas = AnnotationCanvas(image: image)

        // Taille initiale : la moitié des pixels (taille naturelle Retina),
        // bornée à l'écran.
        var contentSize = NSSize(
            width: max(720, image.size.width / 2),
            height: max(440, image.size.height / 2) + 92
        )
        if let screen = NSScreen.main {
            contentSize.width = min(contentSize.width, screen.visibleFrame.width * 0.9)
            contentSize.height = min(contentSize.height, screen.visibleFrame.height * 0.9)
        }

        window = EditorWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = fileURL.lastPathComponent
        window.minSize = NSSize(width: 760, height: 420)
        // AppKit libère lui-même une fenêtre fermée par défaut ; combiné à
        // notre référence forte, cela ferait une double libération (crash à
        // la fermeture). ARC s'en charge très bien tout seul.
        window.isReleasedWhenClosed = false

        super.init()
        window.annotator = self
        window.delegate = self
        buildUI()

        canvas.onWillMutate = { [weak self] in self?.pushUndoSnapshot() }
        canvas.onCrop = { [weak self] rect in self?.applyCrop(rect) }
        canvas.onRequestText = { [weak self] point in self?.promptForText(at: point) }
        canvas.onToolShortcut = { [weak self] index in
            guard let self, let tool = AnnotationTool(rawValue: index) else { return }
            self.canvas.currentTool = tool
            self.toolsControl?.selectedSegment = index
        }
        updateTitle()
    }

    private func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    func windowWillClose(_ notification: Notification) {
        colorObservation = nil
        // Différé : se retirer de la liste ici détruirait le contrôleur (et
        // la fenêtre) au beau milieu de la fermeture en cours.
        DispatchQueue.main.async {
            Self.active.removeAll { $0 === self }
        }
    }

    // MARK: interface

    private func buildUI() {
        let content = NSView()
        window.contentView = content

        // Rangée 1 : les outils.
        let tools = NSSegmentedControl(
            labels: AnnotationTool.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(toolChanged(_:))
        )
        tools.selectedSegment = 0
        tools.toolTip = "Changer d'outil : touches 1 à 9"
        toolsControl = tools

        // Rangée 2 : options et actions.
        let colorWell = NSColorWell()
        colorWell.color = canvas.currentColor
        colorObservation = colorWell.observe(\.color, options: [.new]) { [weak self] well, _ in
            self?.canvas.currentColor = well.color
        }

        let thicknessLabel = NSTextField(labelWithString: "Épaisseur")
        thicknessLabel.font = .systemFont(ofSize: 12)
        thicknessLabel.textColor = .secondaryLabelColor

        let slider = NSSlider(
            value: Double(canvas.currentLineWidth),
            minValue: 2,
            maxValue: 20,
            target: self,
            action: #selector(thicknessChanged(_:))
        )

        let beautifyCheck = NSButton(
            checkboxWithTitle: "Joli fond",
            target: self,
            action: #selector(beautifyChanged(_:))
        )

        let undoButton = NSButton(title: "Annuler", target: self, action: #selector(undoClicked))
        let copyButton = NSButton(title: "Copier", target: self, action: #selector(copyClicked))
        let pinButton = NSButton(title: "Épingler", target: self, action: #selector(pinClicked))
        let saveButton = NSButton(title: "Enregistrer", target: self, action: #selector(saveClicked))
        saveButton.keyEquivalent = "\r"

        let row1 = NSStackView(views: [tools])
        row1.orientation = .horizontal
        row1.alignment = .centerY

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row2 = NSStackView(views: [
            colorWell, thicknessLabel, slider, beautifyCheck, spacer,
            undoButton, copyButton, pinButton, saveButton,
        ])
        row2.orientation = .horizontal
        row2.alignment = .centerY
        row2.spacing = 10

        let toolbar = NSStackView(views: [row1, row2])
        toolbar.orientation = .vertical
        toolbar.alignment = .leading
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        content.addSubview(toolbar)
        content.addSubview(canvas)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            row2.widthAnchor.constraint(
                equalTo: toolbar.widthAnchor, constant: -28
            ),
            colorWell.widthAnchor.constraint(equalToConstant: 44),
            colorWell.heightAnchor.constraint(equalToConstant: 24),
            slider.widthAnchor.constraint(equalToConstant: 140),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    // MARK: actions

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        if let tool = AnnotationTool(rawValue: sender.selectedSegment) {
            canvas.currentTool = tool
        }
    }

    @objc private func thicknessChanged(_ sender: NSSlider) {
        canvas.currentLineWidth = CGFloat(sender.doubleValue)
    }

    @objc private func beautifyChanged(_ sender: NSButton) {
        beautify = sender.state == .on
        canvas.beautifyPreview = beautify
    }

    @objc private func undoClicked() { undo() }
    @objc private func copyClicked() { copyImage() }
    @objc private func saveClicked() { save() }

    @objc private func pinClicked() {
        PinWindowController.pin(image: renderedImage())
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else {
            NSSound.beep()
            return
        }
        redoStack.append(currentSnapshot())
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else {
            NSSound.beep()
            return
        }
        undoStack.append(currentSnapshot())
        restore(snapshot)
    }

    private func currentSnapshot() -> Snapshot {
        (canvas.image, canvas.shapes, canvas.badgeCounter)
    }

    private func restore(_ snapshot: Snapshot) {
        canvas.image = snapshot.0
        canvas.shapes = snapshot.1
        canvas.badgeCounter = snapshot.2
        updateTitle()
    }

    func copyImage() {
        let rendered = renderedImage()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([rendered])
        Toast.shared.show("Copié dans le presse-papiers")
    }

    func save() {
        let rendered = renderedImage()
        guard let data = ImageUtils.pngData(rendered) else {
            Toast.shared.show("Échec de l'enregistrement")
            return
        }
        do {
            try data.write(to: fileURL)
        } catch {
            Toast.shared.show("Échec de l'enregistrement : \(error.localizedDescription)")
            return
        }
        if Settings.autoCopy {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([rendered])
            Toast.shared.show("Enregistré et copié")
        } else {
            Toast.shared.show("Enregistré")
        }
    }

    private func renderedImage() -> NSImage {
        let image = canvas.image
        let shapes = canvas.shapes
        let pixelated = shapes.contains { $0.tool == .pixelate } ? canvas.pixelatedImage : nil
        let flat = NSImage(size: image.size, flipped: false) { _ in
            image.draw(in: NSRect(origin: .zero, size: image.size))
            for shape in shapes {
                ShapeRenderer.draw(shape, pixelatedImage: pixelated)
            }
            return true
        }
        return beautify ? ImageUtils.beautified(flat) : flat
    }

    // MARK: recadrage et texte

    private func applyCrop(_ rect: NSRect) {
        guard rect.width > 10, rect.height > 10,
              let cg = canvas.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        // CGImage a l'origine en HAUT à gauche, nos coordonnées en bas.
        let imageHeight = canvas.image.size.height
        let cropCG = CGRect(
            x: rect.minX,
            y: imageHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        guard let cropped = cg.cropping(to: cropCG) else { return }

        pushUndoSnapshot()
        canvas.image = NSImage(cgImage: cropped, size: rect.size)
        canvas.shapes = canvas.shapes.map { shape in
            var moved = shape
            moved.start.x -= rect.minX
            moved.start.y -= rect.minY
            moved.end.x -= rect.minX
            moved.end.y -= rect.minY
            return moved
        }
        updateTitle()
    }

    private func promptForText(at point: CGPoint) {
        let alert = NSAlert()
        alert.messageText = "Texte de l'annotation"
        alert.addButton(withTitle: "Ajouter")
        alert.addButton(withTitle: "Annuler")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Votre texte"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            canvas.addText(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), at: point)
        }
    }

    private func pushUndoSnapshot() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll() // toute nouvelle action invalide le rétablir
        if undoStack.count > 40 {
            undoStack.removeFirst()
        }
    }

    private func updateTitle() {
        let size = canvas.image.size
        window.title = "\(fileURL.lastPathComponent)  (\(Int(size.width)) × \(Int(size.height)) px)"
    }
}
