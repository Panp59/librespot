import AVFoundation
import Foundation

/// Enregistre le micro en AAC (.m4a), mixé dans la vidéo à l'export.
final class MicRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    /// Horodatage (horloge hôte) du démarrage, pour aligner avec la vidéo.
    private(set) var startTime: Double?

    var isRecording: Bool { recorder?.isRecording ?? false }

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.prepareToRecord()
        guard rec.record() else {
            throw NSError(
                domain: "Clap", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Impossible de démarrer l'enregistrement micro."]
            )
        }
        startTime = CACurrentMediaTime()
        recorder = rec
    }

    func stop() {
        recorder?.stop()
        recorder = nil
    }
}
