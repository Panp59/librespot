import AppKit
import CoreText
import Foundation

// MARK: - Réglages d'export

struct BackgroundPreset {
    let name: String
    let topColor: CGColor
    let bottomColor: CGColor

    static let all: [BackgroundPreset] = [
        BackgroundPreset(
            name: "Bleu nuit",
            topColor: CGColor(red: 0.16, green: 0.22, blue: 0.48, alpha: 1),
            bottomColor: CGColor(red: 0.05, green: 0.06, blue: 0.16, alpha: 1)
        ),
        BackgroundPreset(
            name: "Aurore",
            topColor: CGColor(red: 0.98, green: 0.45, blue: 0.42, alpha: 1),
            bottomColor: CGColor(red: 0.45, green: 0.16, blue: 0.50, alpha: 1)
        ),
        BackgroundPreset(
            name: "Forêt",
            topColor: CGColor(red: 0.13, green: 0.42, blue: 0.34, alpha: 1),
            bottomColor: CGColor(red: 0.04, green: 0.15, blue: 0.13, alpha: 1)
        ),
        BackgroundPreset(
            name: "Graphite",
            topColor: CGColor(gray: 0.22, alpha: 1),
            bottomColor: CGColor(gray: 0.08, alpha: 1)
        ),
        BackgroundPreset(
            name: "Clair",
            topColor: CGColor(gray: 0.96, alpha: 1),
            bottomColor: CGColor(gray: 0.82, alpha: 1)
        ),
    ]
}

enum BackgroundStyle {
    case gradient(BackgroundPreset)
    case solid(CGColor)
    case image(CGImage)
}

struct OutputFormat {
    let name: String
    let size: CGSize

    static let all: [OutputFormat] = [
        OutputFormat(name: "1080p (1920 × 1080)", size: CGSize(width: 1920, height: 1080)),
        OutputFormat(name: "1440p (2560 × 1440)", size: CGSize(width: 2560, height: 1440)),
        OutputFormat(name: "4K (3840 × 2160)", size: CGSize(width: 3840, height: 2160)),
        OutputFormat(name: "Vertical (1080 × 1920)", size: CGSize(width: 1080, height: 1920)),
    ]
}

enum WebcamCorner: Int, CaseIterable {
    case bottomRight = 0, bottomLeft, topRight, topLeft

    var name: String {
        switch self {
        case .bottomRight: return "En bas à droite"
        case .bottomLeft: return "En bas à gauche"
        case .topRight: return "En haut à droite"
        case .topLeft: return "En haut à gauche"
        }
    }
}

enum WebcamShape: Int, CaseIterable {
    case circle = 0, roundedRect

    var name: String {
        switch self {
        case .circle: return "Cercle"
        case .roundedRect: return "Rectangle arrondi"
        }
    }
}

struct ExportSettings {
    var outputSize = CGSize(width: 1920, height: 1080)
    var fps = 30
    /// Marge autour de l'écran, en fraction du plus petit côté de la sortie.
    var paddingFraction: CGFloat = 0.07
    /// Rayon des coins arrondis, en pixels de sortie.
    var cornerRadius: CGFloat = 18
    /// Facteur de zoom maximal sur les clics (1 = zoom désactivé).
    var maxZoom: CGFloat = 1.9
    /// Taille du curseur synthétique (multiplicateur).
    var cursorScale: CGFloat = 2.0
    var background: BackgroundStyle = .gradient(BackgroundPreset.all[0])
    var includeMic = true
    /// Voix off Souffleur. Quand elle est active et disponible, elle remplace
    /// le micro sur la piste audio finale.
    var includeNarration = true

    var showWebcam = true
    var webcamCorner: WebcamCorner = .bottomRight
    /// Taille de la webcam, en fraction du plus petit côté de la sortie.
    var webcamFraction: CGFloat = 0.24
    var webcamShape: WebcamShape = .circle

    var showKeystrokes = true

    /// Rognage (repris de RecordingData, modifiable dans l'éditeur).
    var trimStart: Double = 0
    var trimEnd: Double = 0
}

// MARK: - Composition

/// Dessine une image finale à l'instant t (temps de la vidéo brute) dans un
/// contexte Core Graphics. Utilisé à la fois par l'export et par l'aperçu
/// de l'éditeur, pour un rendu strictement identique.
final class FrameComposer {
    private let data: RecordingData
    private let settings: ExportSettings
    private let planner: CameraPlanner

    init(data: RecordingData, settings: ExportSettings, segments: [ZoomSegment]) {
        self.data = data
        self.settings = settings
        self.planner = CameraPlanner(recording: data, segments: segments, maxZoom: settings.maxZoom)
    }

    func compose(
        into context: CGContext,
        canvasSize: CGSize,
        screenFrame: CGImage?,
        webcamFrame: CGImage?,
        at t: Double
    ) {
        let canvasWidth = canvasSize.width
        let canvasHeight = canvasSize.height

        // Convertit un rectangle « origine en haut à gauche » vers le repère
        // CG (origine en bas à gauche).
        func cgRect(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: canvasHeight - rect.maxY,
                   width: rect.width, height: rect.height)
        }

        // 1. Fond.
        drawBackground(in: context, canvasSize: canvasSize)

        // 2. Emplacement de l'écran : ajustement au ratio source, centré,
        //    avec la marge demandée (repère haut-gauche).
        let padding = settings.paddingFraction * min(canvasWidth, canvasHeight)
        let available = CGRect(x: padding, y: padding,
                               width: canvasWidth - 2 * padding,
                               height: canvasHeight - 2 * padding)
        let sourceSize = CGSize(width: data.pixelWidth, height: data.pixelHeight)
        let fitScale = min(available.width / sourceSize.width, available.height / sourceSize.height)
        let screenSize = CGSize(width: sourceSize.width * fitScale, height: sourceSize.height * fitScale)
        let screenRect = CGRect(
            x: available.midX - screenSize.width / 2,
            y: available.midY - screenSize.height / 2,
            width: screenSize.width,
            height: screenSize.height
        )
        let screenRectCG = cgRect(screenRect)
        let cornerRadius = min(settings.cornerRadius, min(screenRect.width, screenRect.height) / 2)
        let roundedPath = CGPath(
            roundedRect: screenRectCG,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        // 3. Ombre portée sous l'écran.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -12 * canvasHeight / 1080),
            blur: 40 * canvasHeight / 1080,
            color: CGColor(gray: 0, alpha: 0.4)
        )
        context.addPath(roundedPath)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        context.restoreGState()

        // 4. Contenu de l'écran, cadré par la caméra virtuelle.
        let camera = planner.state(at: t)
        let cropSize = CGSize(width: sourceSize.width / camera.zoom,
                              height: sourceSize.height / camera.zoom)
        let cropRect = CGRect(
            x: camera.center.x - cropSize.width / 2,
            y: camera.center.y - cropSize.height / 2,
            width: cropSize.width,
            height: cropSize.height
        )

        if let screenFrame, let cropped = screenFrame.cropping(to: cropRect) {
            context.saveGState()
            context.addPath(roundedPath)
            context.clip()
            context.interpolationQuality = .high
            context.draw(cropped, in: screenRectCG)
            context.restoreGState()
        }

        // 5. Curseur synthétique et ondes de clic (s'ils sont dans le cadre).
        let pixelsPerSourcePixel = screenRect.width / cropRect.width

        func toCanvas(_ p: CGPoint) -> CGPoint? {
            guard cropRect.insetBy(dx: -20, dy: -20).contains(p) else { return nil }
            return CGPoint(
                x: screenRect.minX + (p.x - cropRect.minX) * pixelsPerSourcePixel,
                y: screenRect.minY + (p.y - cropRect.minY) * pixelsPerSourcePixel
            )
        }

        let rippleDuration = 0.45
        for click in data.clicks {
            let age = t - click.t
            guard age >= 0, age <= rippleDuration else { continue }
            if let p = toCanvas(CGPoint(x: click.x, y: click.y)) {
                CursorArtwork.drawClickRipple(
                    in: context, at: p, canvasHeight: canvasHeight,
                    scale: pixelsPerSourcePixel,
                    progress: CGFloat(age / rippleDuration)
                )
            }
        }

        if let cursorCanvas = toCanvas(planner.cursorPosition(at: t)) {
            CursorArtwork.drawArrow(
                in: context, at: cursorCanvas, canvasHeight: canvasHeight,
                scale: pixelsPerSourcePixel * settings.cursorScale
            )
        }

        // 6. Webcam en overlay.
        if settings.showWebcam, let webcamFrame {
            drawWebcam(webcamFrame, in: context, canvasSize: canvasSize, padding: padding)
        }

        // 7. Touches clavier.
        if settings.showKeystrokes {
            let text = Self.keystrokeText(keys: data.keys, at: t)
            if !text.isEmpty {
                drawKeystrokePill(text, in: context, canvasSize: canvasSize)
            }
        }
    }

    // MARK: - Fond

    private func drawBackground(in context: CGContext, canvasSize: CGSize) {
        switch settings.background {
        case .gradient(let preset):
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [preset.topColor, preset.bottomColor] as CFArray,
                locations: [0, 1]
            ) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: canvasSize.height),
                    end: CGPoint(x: 0, y: 0),
                    options: []
                )
            }
        case .solid(let color):
            context.setFillColor(color)
            context.fill(CGRect(origin: .zero, size: canvasSize))
        case .image(let image):
            // Remplissage en conservant le ratio (aspect fill, centré).
            let imageSize = CGSize(width: image.width, height: image.height)
            let scale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
            let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let drawRect = CGRect(
                x: (canvasSize.width - drawSize.width) / 2,
                y: (canvasSize.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            context.saveGState()
            context.interpolationQuality = .high
            context.draw(image, in: drawRect)
            context.restoreGState()
        }
    }

    // MARK: - Webcam

    private func drawWebcam(
        _ frame: CGImage,
        in context: CGContext,
        canvasSize: CGSize,
        padding: CGFloat
    ) {
        let side = settings.webcamFraction * min(canvasSize.width, canvasSize.height)
        let margin = max(padding * 0.5, 16 * canvasSize.height / 1080)

        let isCircle = settings.webcamShape == .circle
        // Cercle : vignette carrée ; rectangle : ratio 4:3.
        let boxSize = isCircle
            ? CGSize(width: side, height: side)
            : CGSize(width: side * 4 / 3, height: side)

        // Position (repère CG, origine en bas à gauche).
        let x: CGFloat
        let y: CGFloat
        switch settings.webcamCorner {
        case .bottomRight:
            x = canvasSize.width - margin - boxSize.width
            y = margin
        case .bottomLeft:
            x = margin
            y = margin
        case .topRight:
            x = canvasSize.width - margin - boxSize.width
            y = canvasSize.height - margin - boxSize.height
        case .topLeft:
            x = margin
            y = canvasSize.height - margin - boxSize.height
        }
        let boxRect = CGRect(x: x, y: y, width: boxSize.width, height: boxSize.height)

        let clipPath: CGPath = isCircle
            ? CGPath(ellipseIn: boxRect, transform: nil)
            : CGPath(roundedRect: boxRect, cornerWidth: 14, cornerHeight: 14, transform: nil)

        // Ombre.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -6 * canvasSize.height / 1080),
            blur: 24 * canvasSize.height / 1080,
            color: CGColor(gray: 0, alpha: 0.45)
        )
        context.addPath(clipPath)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        context.restoreGState()

        // Image recadrée (aspect fill dans la vignette).
        let frameSize = CGSize(width: frame.width, height: frame.height)
        let fillScale = max(boxRect.width / frameSize.width, boxRect.height / frameSize.height)
        let cropSize = CGSize(width: boxRect.width / fillScale, height: boxRect.height / fillScale)
        let cropRect = CGRect(
            x: (frameSize.width - cropSize.width) / 2,
            y: (frameSize.height - cropSize.height) / 2,
            width: cropSize.width,
            height: cropSize.height
        )

        context.saveGState()
        context.addPath(clipPath)
        context.clip()
        context.interpolationQuality = .high
        if let cropped = frame.cropping(to: cropRect) {
            context.draw(cropped, in: boxRect)
        }
        context.restoreGState()

        // Liseré discret.
        context.saveGState()
        context.addPath(clipPath)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
        context.setLineWidth(2 * canvasSize.height / 1080)
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Touches clavier

    /// Texte à afficher à l'instant t : le dernier raccourci seul, ou les
    /// lettres tapées récemment regroupées en « mot ».
    static func keystrokeText(keys: [KeyEvent], at t: Double, window: Double = 1.5) -> String {
        let recent = keys.filter { $0.t <= t && t - $0.t <= window }
        guard !recent.isEmpty else { return "" }

        if let shortcut = recent.last(where: { $0.isShortcut }) {
            // Un raccourci est toujours affiché seul, tant qu'il est récent.
            if recent.last?.isShortcut == true || t - shortcut.t < 0.8 {
                return shortcut.text
            }
        }
        // Frappe normale : concatène les dernières lettres.
        let typed = recent.filter { !$0.isShortcut }.map(\.text).joined()
        return String(typed.suffix(24))
    }

    private func drawKeystrokePill(_ text: String, in context: CGContext, canvasSize: CGSize) {
        let fontSize = canvasSize.height * 0.034
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, [])

        let padH = fontSize * 0.8
        let padV = fontSize * 0.45
        let pillWidth = bounds.width + padH * 2
        let pillHeight = bounds.height + padV * 2
        let pillRect = CGRect(
            x: (canvasSize.width - pillWidth) / 2,
            y: canvasSize.height * 0.05,
            width: pillWidth,
            height: pillHeight
        )

        context.saveGState()
        let path = CGPath(
            roundedRect: pillRect,
            cornerWidth: pillHeight / 2, cornerHeight: pillHeight / 2,
            transform: nil
        )
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0, alpha: 0.6))
        context.fillPath()

        context.textPosition = CGPoint(
            x: pillRect.minX + padH,
            y: pillRect.minY + padV - bounds.minY
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

// MARK: - Contexte de dessin

enum CanvasContext {
    /// Crée un contexte BGRA compatible avec le compositeur.
    static func make(width: Int, height: Int, data: UnsafeMutableRawPointer? = nil, bytesPerRow: Int = 0) -> CGContext? {
        CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}
