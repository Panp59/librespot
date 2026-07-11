import CoreGraphics
import Foundation

/// État de la caméra virtuelle à un instant t : facteur de zoom et centre
/// du cadrage, en pixels de la vidéo source.
struct CameraState {
    var zoom: CGFloat
    var center: CGPoint
}

/// Calcule, image par image, où la caméra virtuelle doit regarder :
/// - zoom automatique autour des clics, avec des transitions douces ;
/// - centre qui suit une version très lissée de la trajectoire souris.
final class CameraPlanner {
    private let sourceSize: CGSize
    private let maxZoom: CGFloat

    /// Fenêtres temporelles (s) pendant lesquelles le zoom est actif.
    private var segments: [(start: Double, end: Double)] = []
    private let easeDuration = 0.7

    /// Trajectoires rééchantillonnées à 60 Hz.
    private let sampleRate = 60.0
    private var cursorTrack: [CGPoint] = []   // lissage léger (curseur)
    private var cameraTrack: [CGPoint] = []   // lissage fort (caméra)
    private var trackStart: Double = 0

    init(recording: RecordingData, maxZoom: CGFloat) {
        self.sourceSize = CGSize(width: recording.pixelWidth, height: recording.pixelHeight)
        self.maxZoom = max(1.0, maxZoom)
        buildSegments(clicks: recording.clicks, duration: recording.duration)
        buildTracks(points: recording.points, duration: recording.duration)
    }

    func state(at t: Double) -> CameraState {
        let zoom = zoomFactor(at: t)
        let center = clampedCenter(position(in: cameraTrack, at: t), zoom: zoom)
        return CameraState(zoom: zoom, center: center)
    }

    /// Position du curseur synthétique (lissage léger, fidèle au geste).
    func cursorPosition(at t: Double) -> CGPoint {
        position(in: cursorTrack, at: t)
    }

    // MARK: - Zoom

    private func buildSegments(clicks: [MouseClick], duration: Double) {
        let holdBefore = 0.35
        let holdAfter = 1.8
        let mergeGap = 1.2

        let windows = clicks
            .map { (start: max(0, $0.t - holdBefore), end: min(duration, $0.t + holdAfter)) }
            .sorted { $0.start < $1.start }

        var merged: [(start: Double, end: Double)] = []
        for window in windows {
            if var last = merged.last, window.start - last.end < mergeGap {
                last.end = max(last.end, window.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(window)
            }
        }
        segments = merged
    }

    private func zoomFactor(at t: Double) -> CGFloat {
        var envelope = 0.0
        for segment in segments {
            let ease = min(easeDuration, (segment.end - segment.start) / 2)
            guard ease > 0 else { continue }
            let rampIn = smoothstep((t - segment.start + ease) / ease)
            let rampOut = smoothstep((segment.end + ease - t) / ease)
            envelope = max(envelope, min(rampIn, rampOut))
        }
        return 1 + (maxZoom - 1) * CGFloat(envelope)
    }

    /// Interpolation douce (0 → 1) avec dérivée nulle aux bords.
    private func smoothstep(_ x: Double) -> Double {
        let clamped = min(max(x, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    // MARK: - Trajectoires

    private func buildTracks(points: [MousePoint], duration: Double) {
        guard !points.isEmpty else {
            let center = CGPoint(x: sourceSize.width / 2, y: sourceSize.height / 2)
            cursorTrack = [center]
            cameraTrack = [center]
            trackStart = 0
            return
        }

        // Rééchantillonnage à cadence fixe (le Timer de capture peut jitterer).
        trackStart = 0
        let count = max(2, Int(duration * sampleRate) + 1)
        var resampled: [CGPoint] = []
        resampled.reserveCapacity(count)
        var index = 0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            while index < points.count - 1 && points[index + 1].t <= t {
                index += 1
            }
            let current = points[index]
            if index < points.count - 1 {
                let next = points[index + 1]
                let span = next.t - current.t
                let fraction = span > 0 ? (t - current.t) / span : 0
                let clamped = min(max(fraction, 0), 1)
                resampled.append(CGPoint(
                    x: current.x + (next.x - current.x) * clamped,
                    y: current.y + (next.y - current.y) * clamped
                ))
            } else {
                resampled.append(CGPoint(x: current.x, y: current.y))
            }
        }

        // Curseur : moyenne glissante courte (~80 ms) pour gommer le bruit
        // sans dénaturer le geste. Caméra : gaussienne large (~0,7 s) pour
        // un mouvement de « steadicam ».
        cursorTrack = boxSmooth(resampled, radius: 2)
        cameraTrack = gaussianSmooth(resampled, sigma: 0.35 * sampleRate)
    }

    private func position(in track: [CGPoint], at t: Double) -> CGPoint {
        guard !track.isEmpty else {
            return CGPoint(x: sourceSize.width / 2, y: sourceSize.height / 2)
        }
        let position = (t - trackStart) * sampleRate
        let lower = Int(floor(position))
        if lower < 0 { return track[0] }
        if lower >= track.count - 1 { return track[track.count - 1] }
        let fraction = CGFloat(position - Double(lower))
        let a = track[lower]
        let b = track[lower + 1]
        return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }

    /// Garde le cadrage entièrement dans l'image source.
    private func clampedCenter(_ center: CGPoint, zoom: CGFloat) -> CGPoint {
        let cropWidth = sourceSize.width / zoom
        let cropHeight = sourceSize.height / zoom
        let x = min(max(center.x, cropWidth / 2), sourceSize.width - cropWidth / 2)
        let y = min(max(center.y, cropHeight / 2), sourceSize.height - cropHeight / 2)
        return CGPoint(x: x, y: y)
    }

    private func boxSmooth(_ input: [CGPoint], radius: Int) -> [CGPoint] {
        guard radius > 0, input.count > 1 else { return input }
        var output = input
        for i in 0..<input.count {
            var sumX: CGFloat = 0
            var sumY: CGFloat = 0
            var n: CGFloat = 0
            for j in max(0, i - radius)...min(input.count - 1, i + radius) {
                sumX += input[j].x
                sumY += input[j].y
                n += 1
            }
            output[i] = CGPoint(x: sumX / n, y: sumY / n)
        }
        return output
    }

    private func gaussianSmooth(_ input: [CGPoint], sigma: Double) -> [CGPoint] {
        guard sigma > 0, input.count > 1 else { return input }
        let radius = Int(sigma * 3)
        guard radius > 0 else { return input }
        var kernel = [Double](repeating: 0, count: 2 * radius + 1)
        var total = 0.0
        for i in -radius...radius {
            let value = exp(-Double(i * i) / (2 * sigma * sigma))
            kernel[i + radius] = value
            total += value
        }
        for i in kernel.indices { kernel[i] /= total }

        var output = input
        for i in 0..<input.count {
            var sumX = 0.0
            var sumY = 0.0
            var weight = 0.0
            for k in -radius...radius {
                let j = i + k
                guard j >= 0, j < input.count else { continue }
                let w = kernel[k + radius]
                sumX += Double(input[j].x) * w
                sumY += Double(input[j].y) * w
                weight += w
            }
            output[i] = CGPoint(x: sumX / weight, y: sumY / weight)
        }
        return output
    }
}
