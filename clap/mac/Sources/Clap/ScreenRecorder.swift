import AVFoundation
import AppKit
import ScreenCaptureKit

/// Capture l'écran principal (curseur masqué) via ScreenCaptureKit et
/// l'encode en H.264 dans un fichier .mov. Nécessite l'autorisation
/// Enregistrement de l'écran.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let sampleQueue = DispatchQueue(label: "fr.adti.clap.capture")

    /// Horodatage (horloge hôte, secondes) de la première image écrite.
    /// Sert de temps zéro pour la souris et le micro.
    private(set) var firstFrameTime: Double?
    private(set) var pixelSize = CGSize.zero

    var isRecording: Bool { stream != nil }

    func start(to url: URL, completion: @escaping (Error?) -> Void) {
        try? FileManager.default.removeItem(at: url)
        firstFrameTime = nil

        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            let mainID = CGMainDisplayID()
            guard let display = content?.displays.first(where: { $0.displayID == mainID })
                ?? content?.displays.first
            else {
                let err = NSError(
                    domain: "Clap", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Aucun écran disponible pour la capture."]
                )
                DispatchQueue.main.async { completion(err) }
                return
            }

            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let width = Int(CGFloat(display.width) * scale)
            let height = Int(CGFloat(display.height) * scale)
            self.pixelSize = CGSize(width: width, height: height)

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.showsCursor = false // le curseur est redessiné au rendu
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 8

            do {
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                let settings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                    AVVideoCompressionPropertiesKey: [
                        // Capture brute : débit généreux, la compression
                        // finale se fait à l'export.
                        AVVideoAverageBitRateKey: 40_000_000
                    ],
                ]
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                input.expectsMediaDataInRealTime = true
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input, sourcePixelBufferAttributes: nil
                )
                writer.add(input)
                self.writer = writer
                self.input = input
                self.adaptor = adaptor
            } catch {
                DispatchQueue.main.async { completion(error) }
                return
            }

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.sampleQueue)
            } catch {
                DispatchQueue.main.async { completion(error) }
                return
            }
            self.stream = stream
            stream.startCapture { error in
                DispatchQueue.main.async {
                    if error != nil { self.stream = nil }
                    completion(error)
                }
            }
        }
    }

    func stop(completion: @escaping (Error?) -> Void) {
        guard let stream else {
            completion(nil)
            return
        }
        stream.stopCapture { [weak self] _ in
            guard let self else { return }
            self.sampleQueue.async {
                guard let writer = self.writer else {
                    DispatchQueue.main.async {
                        self.stream = nil
                        completion(nil)
                    }
                    return
                }
                self.input?.markAsFinished()
                let finish = {
                    let error = writer.status == .failed ? writer.error : nil
                    DispatchQueue.main.async {
                        self.stream = nil
                        self.writer = nil
                        self.input = nil
                        self.adaptor = nil
                        completion(error)
                    }
                }
                if writer.status == .writing {
                    writer.finishWriting(completionHandler: finish)
                } else {
                    finish()
                }
            }
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // ScreenCaptureKit envoie aussi des images « incomplètes » (écran
        // inchangé) sans données : on ne garde que les images complètes.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let statusRaw = attachments.first?[.status] as? Int,
            statusRaw == SCFrameStatus.complete.rawValue,
            let pixelBuffer = sampleBuffer.imageBuffer
        else { return }

        guard let writer, let input, let adaptor else { return }

        let pts = sampleBuffer.presentationTimeStamp
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            firstFrameTime = pts.seconds
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        adaptor.append(pixelBuffer, withPresentationTime: pts)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Clap: capture interrompue: \(error)")
        DispatchQueue.main.async { [weak self] in
            self?.stream = nil
        }
    }
}
