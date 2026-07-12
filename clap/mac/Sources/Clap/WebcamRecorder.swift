import AVFoundation
import Foundation

/// Enregistre la webcam en H.264 (.mov), avec des horodatages sur l'horloge
/// hôte pour un alignement précis avec la capture d'écran.
final class WebcamRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let dataOutput = AVCaptureVideoDataOutput()
    private let sampleQueue = DispatchQueue(label: "fr.adti.clap.webcam")

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?

    /// Horodatage (horloge hôte, secondes) de la première image écrite.
    private(set) var firstFrameTime: Double?
    private(set) var isRecording = false
    private var outputURL: URL?

    /// Session exposée pour l'aperçu en direct (cadrage pendant
    /// l'enregistrement).
    var captureSession: AVCaptureSession { session }

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        firstFrameTime = nil

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw NSError(
                domain: "Clap", code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Aucune webcam détectée."]
            )
        }
        let deviceInput = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        session.sessionPreset = .high
        for existing in session.inputs { session.removeInput(existing) }
        for existing in session.outputs { session.removeOutput(existing) }
        guard session.canAddInput(deviceInput), session.canAddOutput(dataOutput) else {
            session.commitConfiguration()
            throw NSError(
                domain: "Clap", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Impossible de configurer la webcam."]
            )
        }
        session.addInput(deviceInput)
        dataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        session.addOutput(dataOutput)
        session.commitConfiguration()

        // Le writer est créé à la première image reçue : ses dimensions
        // correspondent alors exactement au flux réel (activeFormat peut
        // différer de ce que la sortie délivre).
        self.outputURL = url
        isRecording = true
        // startRunning est bloquant : hors du thread principal.
        sampleQueue.async {
            self.session.startRunning()
        }
    }

    private func createWriter(from sampleBuffer: CMSampleBuffer) {
        guard let url = outputURL, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: CVPixelBufferGetWidth(pixelBuffer),
                AVVideoHeightKey: CVPixelBufferGetHeight(pixelBuffer),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            self.writer = writer
            self.input = input
        } catch {
            NSLog("Clap: création du writer webcam impossible: \(error)")
        }
    }

    func stop(completion: @escaping () -> Void) {
        guard isRecording else {
            completion()
            return
        }
        isRecording = false
        sampleQueue.async {
            self.session.stopRunning()
            guard let writer = self.writer else {
                DispatchQueue.main.async { completion() }
                return
            }
            self.input?.markAsFinished()
            let finish = {
                self.writer = nil
                self.input = nil
                DispatchQueue.main.async { completion() }
            }
            if writer.status == .writing {
                writer.finishWriting(completionHandler: finish)
            } else {
                finish()
            }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isRecording else { return }
        if writer == nil { createWriter(from: sampleBuffer) }
        guard let writer, let input else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            firstFrameTime = pts.seconds
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }
}
