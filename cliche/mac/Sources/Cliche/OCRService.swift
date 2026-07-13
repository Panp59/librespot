import AppKit
import Vision

/// Extraction de texte locale via Vision (aucune donnée ne quitte le Mac).
enum OCRService {
    /// Reconnaît le texte de l'image et l'envoie au presse-papiers.
    /// `completion` reçoit le texte (ou nil si rien n'a été trouvé).
    static func extractText(from image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["fr-FR", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let lines: [String] = (request.results ?? []).compactMap {
                $0.topCandidates(1).first?.string
            }
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                completion(text.isEmpty ? nil : text)
            }
        }
    }

    /// OCR + presse-papiers + toast, le flux complet de l'action rapide.
    static func extractAndCopy(from image: NSImage) {
        Toast.shared.show("Reconnaissance du texte...")
        extractText(from: image) { text in
            guard let text else {
                Toast.shared.show("Aucun texte détecté dans la capture")
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            let count = text.components(separatedBy: "\n").count
            Toast.shared.show(count == 1
                ? "Texte copié dans le presse-papiers"
                : "\(count) lignes copiées dans le presse-papiers")
        }
    }
}
