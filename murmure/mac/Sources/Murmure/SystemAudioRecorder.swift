import AVFoundation
import Foundation
import ScreenCaptureKit

/// Capture l'audio système (Teams, Zoom, navigateur…) via ScreenCaptureKit
/// et l'écrit dans un fichier .caf. Nécessite l'autorisation Enregistrement
/// de l'écran (c'est elle qui couvre aussi l'audio système).
final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    // Accédés uniquement sur sampleQueue.
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private let sampleQueue = DispatchQueue(label: "fr.adti.murmure.system-audio")
    /// Horodatage (horloge hôte, secondes) du premier échantillon écrit,
    /// pour synchroniser avec la piste micro.
    private(set) var firstSampleTime: Double?

    var isRecording: Bool { stream != nil }

    func start(to url: URL, completion: @escaping (Error?) -> Void) {
        try? FileManager.default.removeItem(at: url)
        firstSampleTime = nil
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            guard let display = content?.displays.first else {
                let err = NSError(
                    domain: "Murmure", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Aucun écran disponible pour la capture audio système."]
                )
                DispatchQueue.main.async { completion(err) }
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 1
            // On ne veut que l'audio : vidéo minimale, une image par seconde.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            do {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.sampleQueue)
            } catch {
                DispatchQueue.main.async { completion(error) }
                return
            }

            // outputURL/audioFile ne vivent que sur sampleQueue.
            self.sampleQueue.async {
                self.outputURL = url
                self.audioFile = nil
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

    func stop(completion: @escaping (URL?) -> Void) {
        guard let stream else {
            completion(nil)
            return
        }
        stream.stopCapture { [weak self] _ in
            guard let self else { return }
            self.sampleQueue.async {
                let url = self.audioFile != nil ? self.outputURL : nil
                self.audioFile = nil
                self.outputURL = nil
                DispatchQueue.main.async {
                    self.stream = nil
                    completion(url)
                }
            }
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              CMSampleBufferIsValid(sampleBuffer),
              let url = outputURL,
              let absd = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              let format = AVAudioFormat(
                  standardFormatWithSampleRate: absd.mSampleRate,
                  channels: absd.mChannelsPerFrame
              )
        else { return }
        do {
            // L'écriture se fait DANS la closure : le buffer « no copy »
            // n'est valide que tant que la liste de buffers est retenue.
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                guard let pcm = AVAudioPCMBuffer(
                    pcmFormat: format,
                    bufferListNoCopy: audioBufferList.unsafePointer
                ) else { return }
                if self.audioFile == nil {
                    self.audioFile = try AVAudioFile(forWriting: url, settings: pcm.format.settings)
                    self.firstSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                }
                try self.audioFile?.write(from: pcm)
            }
        } catch {
            NSLog("Murmure: erreur d'écriture de l'audio système: \(error)")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Murmure: capture audio système interrompue: \(error)")
        DispatchQueue.main.async { [weak self] in
            self?.stream = nil
        }
    }
}

