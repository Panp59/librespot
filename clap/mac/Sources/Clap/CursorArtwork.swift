import CoreGraphics
import Foundation

/// Dessin du curseur synthétique (flèche macOS stylisée) et des ondes de clic.
enum CursorArtwork {
    /// Flèche définie dans un repère y vers le bas, pointe en (0, 0),
    /// environ 12 × 19 unités (≈ pixels à l'échelle 1).
    static let arrowPath: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 16.9))
        path.addLine(to: CGPoint(x: 4.2, y: 13.1))
        path.addLine(to: CGPoint(x: 6.9, y: 19.3))
        path.addLine(to: CGPoint(x: 9.5, y: 18.2))
        path.addLine(to: CGPoint(x: 6.8, y: 12.1))
        path.addLine(to: CGPoint(x: 12.3, y: 12.0))
        path.closeSubpath()
        return path
    }()

    /// Dessine la flèche dans un contexte CG non retourné (origine en bas à
    /// gauche). `point` est la position de la pointe en coordonnées « écran »
    /// (origine en haut à gauche du canevas).
    static func drawArrow(
        in context: CGContext,
        at point: CGPoint,
        canvasHeight: CGFloat,
        scale: CGFloat
    ) {
        context.saveGState()
        context.translateBy(x: point.x, y: canvasHeight - point.y)
        // Le tracé est défini y vers le bas : on inverse l'axe vertical.
        context.scaleBy(x: scale, y: -scale)

        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3,
                          color: CGColor(gray: 0, alpha: 0.4))
        context.addPath(arrowPath)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()

        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(arrowPath)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(1.4)
        context.setLineJoin(.round)
        context.strokePath()

        context.restoreGState()
    }

    /// Onde circulaire émise par un clic. `progress` va de 0 (instant du
    /// clic) à 1 (fin de l'animation).
    static func drawClickRipple(
        in context: CGContext,
        at point: CGPoint,
        canvasHeight: CGFloat,
        scale: CGFloat,
        progress: CGFloat
    ) {
        let clamped = min(max(progress, 0), 1)
        let radius = (8 + 26 * clamped) * scale
        let alpha = 0.55 * (1 - clamped)
        let center = CGPoint(x: point.x, y: canvasHeight - point.y)

        context.saveGState()
        context.setStrokeColor(CGColor(gray: 1, alpha: alpha))
        context.setLineWidth(2.5 * scale * (1 - 0.5 * clamped))
        context.strokeEllipse(in: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.restoreGState()
    }
}
