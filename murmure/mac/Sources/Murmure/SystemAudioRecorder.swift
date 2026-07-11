import AVFoundation
import Foundation
import ScreenCaptureKit

/// Capture l'audio système (Teams, Zoom, navigateur…) via ScreenCaptureKit
/// et l'écrit dans un fichier .caf. Nécessite l'autorisation Enregistrement
/// de l'écran (c'est elle qui couvre aussi l'audio système).
final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private let sampleQueue = DispatchQueue(label: "fr.adti.murmure.system-audio")
    private(set) var outputURL: URL?

    var isRecording: Bool { stream != nil }

    func start(to url: URL, completion: @escaping (Error?) -> Void) {
        try? FileManager.default.removeItem(at: url)
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

            self.outputURL = url
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
        let url = outputURL
        stream.stopCapture { [weak self] _ in
            self?.sampleQueue.async {
                self?.audioFile = nil
                DispatchQueue.main.async {
                    self?.stream = nil
                    self?.outputURL = nil
                    completion(url)
                }
            }
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              sampleBuffer.isValid,
              let pcm = sampleBuffer.asPCMBuffer,
              let url = outputURL
        else { return }
        do {
            if audioFile == nil {
                audioFile = try AVAudioFile(forWriting: url, settings: pcm.format.settings)
            }
            try audioFile?.write(from: pcm)
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

extension CMSampleBuffer {
    /// Convertit un CMSampleBuffer audio en AVAudioPCMBuffer (sans copie).
    var asPCMBuffer: AVAudioPCMBuffer? {
        try? self.withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
            guard let absd = self.formatDescription?.audioStreamBasicDescription else { return nil }
            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: absd.mSampleRate,
                channels: absd.mChannelsPerFrame
            ) else { return nil }
            return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer)
        }
    }
}
