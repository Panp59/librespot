import AVFoundation
import AppKit
import VideoToolbox

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
    var background = BackgroundPreset.all[0]
    var includeMic = true
}

// MARK: - Renderer

/// Fabrique la vidéo finale : fond dégradé, écran encadré avec coins
/// arrondis et ombre, caméra virtuelle (zooms sur les clics), curseur
/// synthétique lissé, ondes de clic, et piste micro éventuelle.
final class Renderer {
    private let session: RecordingSession
    private let data: RecordingData
    private let settings: ExportSettings
    private let planner: CameraPlanner

    /// Progression 0 → 1, appelée sur le thread principal.
    var onProgress: ((Double) -> Void)?

    private let renderQueue = DispatchQueue(label: "fr.adti.clap.render")
    private let audioQueue = DispatchQueue(label: "fr.adti.clap.render-audio")

    init(session: RecordingSession, data: RecordingData, settings: ExportSettings) {
        self.session = session
        self.data = data
        self.settings = settings
        self.planner = CameraPlanner(recording: data, maxZoom: settings.maxZoom)
    }

    func export(to outputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        renderQueue.async {
            do {
                try self.runExport(to: outputURL, completion: completion)
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Boucle d'export

    private func runExport(to outputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) throws {
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVURLAsset(url: session.rawVideoURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw NSError(
                domain: "Clap", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "La vidéo brute est introuvable ou vide."]
            )
        }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(readerOutput)

        let width = Int(settings.outputSize.width)
        let height = Int(settings.outputSize.height)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let bitsPerPixel = 0.12 // ≈ 12 Mbit/s en 1080p30
        let bitrate = Int(Double(width * height * settings.fps) * bitsPerPixel)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ]
        )
        writer.add(videoInput)

        // Piste audio (micro) éventuelle.
        var audioReader: AVAssetReader?
        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        var audioShift = CMTime.zero

        if settings.includeMic, data.hasMic,
           FileManager.default.fileExists(atPath: session.micURL.path) {
            let micAsset = AVURLAsset(url: session.micURL)
            if let micTrack = micAsset.tracks(withMediaType: .audio).first {
                let micReader = try AVAssetReader(asset: micAsset)
                let micOutput = AVAssetReaderTrackOutput(
                    track: micTrack,
                    outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM]
                )
                micReader.add(micOutput)
                // Alignement : le micro démarre un peu avant la première
                // image vidéo (micOffset > 0) → on saute ce début, puis on
                // recale les horodatages sur zéro.
                if data.micOffset > 0 {
                    let skip = CMTime(seconds: data.micOffset, preferredTimescale: 44_100)
                    micReader.timeRange = CMTimeRange(
                        start: skip,
                        duration: CMTime(seconds: data.duration, preferredTimescale: 44_100)
                    )
                    audioShift = skip
                } else {
                    // Micro démarré après la vidéo : on décale l'audio.
                    audioShift = CMTime(seconds: data.micOffset, preferredTimescale: 44_100)
                }
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: 44_100.0,
                    AVEncoderBitRateKey: 128_000,
                ])
                writer.add(input)
                audioReader = micReader
                audioOutput = micOutput
                audioInput = input
            }
        }

        guard reader.startReading() else {
            throw reader.error ?? NSError(
                domain: "Clap", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Impossible de lire la vidéo brute."]
            )
        }
        audioReader?.startReading()

        guard writer.startWriting() else {
            throw writer.error ?? NSError(
                domain: "Clap", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Impossible de créer le fichier de sortie."]
            )
        }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = max(1, Int(data.duration * Double(settings.fps)))
        var frameIndex = 0
        var currentImage: CGImage?
        var pendingSample = readerOutput.copyNextSampleBuffer()

        let pendingInputs = Atomic(audioInput == nil ? 1 : 2)
        let finishIfDone = {
            guard pendingInputs.decrementAndGet() == 0 else { return }
            reader.cancelReading()
            audioReader?.cancelReading()
            writer.finishWriting {
                DispatchQueue.main.async {
                    if writer.status == .completed {
                        completion(.success(outputURL))
                    } else {
                        completion(.failure(writer.error ?? NSError(
                            domain: "Clap", code: 6,
                            userInfo: [NSLocalizedDescriptionKey: "L'export a échoué."]
                        )))
                    }
                }
            }
        }

        videoInput.requestMediaDataWhenReady(on: renderQueue) { [weak self] in
            guard let self else { return }
            while videoInput.isReadyForMoreMediaData {
                if frameIndex >= totalFrames {
                    videoInput.markAsFinished()
                    finishIfDone()
                    return
                }
                let t = Double(frameIndex) / Double(self.settings.fps)

                // Avance la lecture source jusqu'à l'image affichée à t.
                // (ScreenCaptureKit ne produit une image que quand l'écran
                // change : la dernière image reste valable entre-temps.)
                while let sample = pendingSample,
                      CMSampleBufferGetPresentationTimeStamp(sample).seconds <= t {
                    if let imageBuffer = sample.imageBuffer {
                        var cgImage: CGImage?
                        VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil, imageOut: &cgImage)
                        if let cgImage { currentImage = cgImage }
                    }
                    pendingSample = readerOutput.copyNextSampleBuffer()
                }

                guard let pool = adaptor.pixelBufferPool else { return }
                var pixelBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                guard let pixelBuffer else { return }

                self.render(frame: currentImage, at: t, into: pixelBuffer)

                let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(self.settings.fps))
                adaptor.append(pixelBuffer, withPresentationTime: pts)
                frameIndex += 1

                if frameIndex % 15 == 0 || frameIndex == totalFrames {
                    let progress = Double(frameIndex) / Double(totalFrames)
                    DispatchQueue.main.async { self.onProgress?(progress) }
                }
            }
        }

        if let audioInput, let audioOutput {
            let shift = audioShift
            audioInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioInput.isReadyForMoreMediaData {
                    guard let sample = audioOutput.copyNextSampleBuffer() else {
                        audioInput.markAsFinished()
                        finishIfDone()
                        return
                    }
                    let adjusted = shift == .zero ? sample : (Self.shifted(sample, by: shift) ?? sample)
                    audioInput.append(adjusted)
                }
            }
        }
    }

    /// Décale les horodatages d'un échantillon audio de -offset.
    private static func shifted(_ sample: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        var count = 0
        CMSampleBufferGetSampleTimingInfoArray(
            sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count
        )
        guard count > 0 else { return nil }
        var infos = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(
            sample, entryCount: count, arrayToFill: &infos, entriesNeededOut: &count
        )
        for i in 0..<count {
            infos[i].presentationTimeStamp = infos[i].presentationTimeStamp - offset
            if infos[i].decodeTimeStamp.isValid {
                infos[i].decodeTimeStamp = infos[i].decodeTimeStamp - offset
            }
        }
        var result: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sample,
            sampleTimingEntryCount: count,
            sampleTimingArray: &infos,
            sampleBufferOut: &result
        )
        return result
    }

    // MARK: - Composition d'une image

    private func render(frame: CGImage?, at t: Double, into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let canvasWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let canvasHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(canvasWidth),
            height: Int(canvasHeight),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        // Convertit un rectangle « origine en haut à gauche » vers le repère
        // CG (origine en bas à gauche).
        func cgRect(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: canvasHeight - rect.maxY,
                   width: rect.width, height: rect.height)
        }

        // 1. Fond dégradé.
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [settings.background.topColor, settings.background.bottomColor] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: canvasHeight),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }

        // 2. Emplacement de l'écran : ajustement au ratio source, centré,
        //    avec la marge demandée (repère haut-gauche).
        let padding = settings.paddingFraction * min(canvasWidth, canvasHeight)
        let available = CGRect(x: padding, y: padding,
                               width: canvasWidth - 2 * padding,
                               height: canvasHeight - 2 * padding)
        let sourceSize = CGSize(width: data.pixelWidth, height: data.pixelHeight)
        let scale = min(available.width / sourceSize.width, available.height / sourceSize.height)
        let screenSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let screenRect = CGRect(
            x: available.midX - screenSize.width / 2,
            y: available.midY - screenSize.height / 2,
            width: screenSize.width,
            height: screenSize.height
        )
        let screenRectCG = cgRect(screenRect)
        let roundedPath = CGPath(
            roundedRect: screenRectCG,
            cornerWidth: settings.cornerRadius,
            cornerHeight: settings.cornerRadius,
            transform: nil
        )

        // 3. Ombre portée sous l'écran.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -12),
            blur: 40,
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

        if let frame, let cropped = frame.cropping(to: cropRect) {
            context.saveGState()
            context.addPath(roundedPath)
            context.clip()
            context.interpolationQuality = .high
            context.draw(cropped, in: screenRectCG)
            context.restoreGState()
        }

        // 5. Curseur synthétique et ondes de clic (uniquement s'ils sont
        //    dans le cadrage).
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
                    in: context,
                    at: p,
                    canvasHeight: canvasHeight,
                    scale: pixelsPerSourcePixel,
                    progress: CGFloat(age / rippleDuration)
                )
            }
        }

        if let cursorCanvas = toCanvas(planner.cursorPosition(at: t)) {
            CursorArtwork.drawArrow(
                in: context,
                at: cursorCanvas,
                canvasHeight: canvasHeight,
                scale: pixelsPerSourcePixel * settings.cursorScale
            )
        }
    }
}

/// Petit compteur thread-safe pour synchroniser la fin des pistes.
final class Atomic {
    private var value: Int
    private let lock = NSLock()

    init(_ value: Int) {
        self.value = value
    }

    func decrementAndGet() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value -= 1
        return value
    }
}
