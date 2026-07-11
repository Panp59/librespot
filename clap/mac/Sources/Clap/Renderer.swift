import AVFoundation
import AppKit
import VideoToolbox

/// Fabrique la vidéo finale à partir d'une session : composition via
/// FrameComposer (fond, caméra virtuelle, curseur, webcam, touches) à
/// cadence fixe, plus la piste micro alignée. Export annulable.
final class Renderer {
    private let session: RecordingSession
    private let data: RecordingData
    private let settings: ExportSettings
    private let composer: FrameComposer

    /// Progression 0 → 1, appelée sur le thread principal.
    var onProgress: ((Double) -> Void)?

    private let renderQueue = DispatchQueue(label: "fr.adti.clap.render")
    private let audioQueue = DispatchQueue(label: "fr.adti.clap.render-audio")
    private let cancelled = AtomicFlag()

    init(session: RecordingSession, data: RecordingData, settings: ExportSettings, segments: [ZoomSegment]) {
        self.session = session
        self.data = data
        self.settings = settings
        self.composer = FrameComposer(data: data, settings: settings, segments: segments)
    }

    func cancel() {
        cancelled.set()
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

    static var cancelledError: Error {
        NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
                userInfo: [NSLocalizedDescriptionKey: "Export annulé."])
    }

    // MARK: - Lecture séquentielle d'une piste vidéo

    /// Fait avancer un lecteur de piste vidéo et fournit l'image affichée à
    /// un instant donné (la dernière image dont le timestamp est ≤ t).
    private final class TrackFollower {
        private let output: AVAssetReaderTrackOutput
        private var pending: CMSampleBuffer?
        private(set) var currentImage: CGImage?

        init(output: AVAssetReaderTrackOutput) {
            self.output = output
            self.pending = output.copyNextSampleBuffer()
        }

        func image(at t: Double) -> CGImage? {
            while let sample = pending,
                  CMSampleBufferGetPresentationTimeStamp(sample).seconds <= t {
                if let buffer = sample.imageBuffer {
                    var cgImage: CGImage?
                    VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &cgImage)
                    if let cgImage { currentImage = cgImage }
                }
                pending = output.copyNextSampleBuffer()
            }
            return currentImage
        }
    }

    // MARK: - Boucle d'export

    private func runExport(to outputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) throws {
        try? FileManager.default.removeItem(at: outputURL)

        let trimStart = max(0, settings.trimStart)
        let trimEnd = min(data.duration, settings.trimEnd > 0 ? settings.trimEnd : data.duration)
        let exportDuration = max(0.1, trimEnd - trimStart)

        // Piste écran.
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

        // Piste webcam éventuelle.
        var webcamReader: AVAssetReader?
        var webcamOutput: AVAssetReaderTrackOutput?
        if settings.showWebcam, data.hasWebcam,
           FileManager.default.fileExists(atPath: session.webcamURL.path) {
            let webcamAsset = AVURLAsset(url: session.webcamURL)
            if let track = webcamAsset.tracks(withMediaType: .video).first {
                let r = try AVAssetReader(asset: webcamAsset)
                let o = AVAssetReaderTrackOutput(
                    track: track,
                    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                )
                r.add(o)
                webcamReader = r
                webcamOutput = o
            }
        }

        // Sortie.
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

        // Piste audio (micro) éventuelle, alignée sur la vidéo rognée.
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
                // Position, dans le fichier micro, de l'instant trimStart :
                // le micro démarre micOffset secondes avant la vidéo.
                let skip = data.micOffset + trimStart
                if skip > 0 {
                    micReader.timeRange = CMTimeRange(
                        start: CMTime(seconds: skip, preferredTimescale: 44_100),
                        duration: CMTime(seconds: exportDuration, preferredTimescale: 44_100)
                    )
                }
                audioShift = CMTime(seconds: skip, preferredTimescale: 44_100)
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
        webcamReader?.startReading()
        audioReader?.startReading()

        guard writer.startWriting() else {
            throw writer.error ?? NSError(
                domain: "Clap", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Impossible de créer le fichier de sortie."]
            )
        }
        writer.startSession(atSourceTime: .zero)

        let screenFollower = TrackFollower(output: readerOutput)
        let webcamFollower = webcamOutput.map { TrackFollower(output: $0) }
        let webcamOffset = data.webcamOffset

        let totalFrames = max(1, Int(exportDuration * Double(settings.fps)))
        var frameIndex = 0

        let cancelled = self.cancelled
        let pendingInputs = AtomicCounter(audioInput == nil ? 1 : 2)
        let cleanupReaders = {
            reader.cancelReading()
            webcamReader?.cancelReading()
            audioReader?.cancelReading()
        }
        let finishIfDone = {
            guard pendingInputs.decrementAndGet() == 0 else { return }
            cleanupReaders()
            if cancelled.isSet {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: outputURL)
                DispatchQueue.main.async { completion(.failure(Renderer.cancelledError)) }
                return
            }
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
                if frameIndex >= totalFrames || cancelled.isSet {
                    videoInput.markAsFinished()
                    finishIfDone()
                    return
                }
                // Temps dans la vidéo brute (le rognage décale l'origine).
                let t = trimStart + Double(frameIndex) / Double(self.settings.fps)

                let screenImage = screenFollower.image(at: t)
                let webcamImage = webcamFollower?.image(at: t + webcamOffset)

                guard let pool = adaptor.pixelBufferPool else { return }
                var pixelBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                guard let pixelBuffer else { return }

                CVPixelBufferLockBaseAddress(pixelBuffer, [])
                if let context = CanvasContext.make(
                    width: Int(self.settings.outputSize.width),
                    height: Int(self.settings.outputSize.height),
                    data: CVPixelBufferGetBaseAddress(pixelBuffer),
                    bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer)
                ) {
                    self.composer.compose(
                        into: context,
                        canvasSize: self.settings.outputSize,
                        screenFrame: screenImage,
                        webcamFrame: webcamImage,
                        at: t
                    )
                }
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

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
                    if cancelled.isSet {
                        audioInput.markAsFinished()
                        finishIfDone()
                        return
                    }
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
}

// MARK: - Petits utilitaires thread-safe

final class AtomicCounter {
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

final class AtomicFlag {
    private var value = false
    private let lock = NSLock()

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        value = true
    }
}
