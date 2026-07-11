import AVFoundation
import Foundation

/// Enregistre le micro en WAV 16 kHz mono 16 bits (le format attendu par Whisper).
final class MicRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private(set) var currentURL: URL?

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
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.prepareToRecord()
        guard rec.record() else {
            throw NSError(
                domain: "Murmure", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Impossible de démarrer l'enregistrement micro."]
            )
        }
        recorder = rec
        currentURL = url
    }

    /// Arrête l'enregistrement et retourne (fichier, durée en secondes).
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let rec = recorder, let url = currentURL else { return nil }
        let duration = rec.currentTime
        rec.stop()
        recorder = nil
        currentURL = nil
        return (url, duration)
    }
}
