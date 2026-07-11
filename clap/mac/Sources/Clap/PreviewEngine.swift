import AVFoundation
import AppKit

/// Rend des images d'aperçu pour l'éditeur, en réutilisant exactement le
/// même FrameComposer que l'export (WYSIWYG). Les demandes sont coalescées :
/// pendant un scrub rapide, seule la dernière position est rendue.
final class PreviewEngine {
    private let data: RecordingData
    private let screenGenerator: AVAssetImageGenerator
    private let webcamGenerator: AVAssetImageGenerator?

    private let queue = DispatchQueue(label: "fr.adti.clap.preview")
    private var composer: FrameComposer
    private var canvasSize: CGSize
    private var pendingRequest: (t: Double, exact: Bool)?
    private var busy = false
    private var completion: ((NSImage) -> Void)?

    init(session: RecordingSession, data: RecordingData, composer: FrameComposer, canvasSize: CGSize) {
        self.data = data
        self.composer = composer
        self.canvasSize = canvasSize

        let asset = AVURLAsset(url: session.rawVideoURL)
        screenGenerator = AVAssetImageGenerator(asset: asset)
        screenGenerator.appliesPreferredTrackTransform = true

        if data.hasWebcam, FileManager.default.fileExists(atPath: session.webcamURL.path) {
            let webcamAsset = AVURLAsset(url: session.webcamURL)
            let generator = AVAssetImageGenerator(asset: webcamAsset)
            generator.appliesPreferredTrackTransform = true
            webcamGenerator = generator
        } else {
            webcamGenerator = nil
        }
    }

    /// À appeler quand un réglage change (le composeur encapsule les
    /// réglages et les segments de zoom).
    func update(composer: FrameComposer) {
        queue.async { self.composer = composer }
    }

    /// Callback (thread principal) qui reçoit chaque image rendue.
    func onFrame(_ handler: @escaping (NSImage) -> Void) {
        queue.async { self.completion = handler }
    }

    /// Demande le rendu de l'instant t. `exact` : image précise (scrub) ou
    /// tolérance large (lecture, plus rapide).
    func requestFrame(at t: Double, exact: Bool) {
        queue.async {
            self.pendingRequest = (t, exact)
            self.processIfIdle()
        }
    }

    // MARK: - File de rendu (sur `queue`)

    private func processIfIdle() {
        guard !busy, let request = pendingRequest else { return }
        pendingRequest = nil
        busy = true

        let tolerance = request.exact
            ? CMTime.zero
            : CMTime(seconds: 0.3, preferredTimescale: 600)
        screenGenerator.requestedTimeToleranceBefore = tolerance
        screenGenerator.requestedTimeToleranceAfter = tolerance

        let screenTime = CMTime(seconds: min(max(0, request.t), data.duration), preferredTimescale: 600)
        let screenImage = try? screenGenerator.copyCGImage(at: screenTime, actualTime: nil)

        var webcamImage: CGImage?
        if let webcamGenerator {
            webcamGenerator.requestedTimeToleranceBefore = tolerance
            webcamGenerator.requestedTimeToleranceAfter = tolerance
            let webcamTime = CMTime(
                seconds: max(0, request.t + data.webcamOffset),
                preferredTimescale: 600
            )
            webcamImage = try? webcamGenerator.copyCGImage(at: webcamTime, actualTime: nil)
        }

        if let context = CanvasContext.make(
            width: Int(canvasSize.width), height: Int(canvasSize.height)
        ) {
            composer.compose(
                into: context,
                canvasSize: canvasSize,
                screenFrame: screenImage,
                webcamFrame: webcamImage,
                at: request.t
            )
            if let cgImage = context.makeImage() {
                let image = NSImage(cgImage: cgImage, size: canvasSize)
                let handler = completion
                DispatchQueue.main.async { handler?(image) }
            }
        }

        busy = false
        // Une nouvelle demande a pu arriver pendant le rendu.
        processIfIdle()
    }
}
