import AppKit

/// Pilote l'outil système /usr/sbin/screencapture : c'est lui qui fournit
/// la sélection de zone au lasso, la capture de fenêtre au survol, etc.
/// Résultat : les mêmes interactions que l'outil natif, zéro code fragile.
final class CaptureManager {
    enum Mode {
        case area
        case window
        case screen
    }

    private(set) var isCapturing = false

    /// Lance une capture. `completion` est appelé sur le main thread avec
    /// l'URL du fichier créé, ou nil si l'utilisateur a annulé (Échap).
    func capture(mode: Mode, completion: @escaping (URL?) -> Void) {
        guard !isCapturing else { return }
        isCapturing = true

        let url = Self.newFileURL()
        var args: [String] = []
        switch mode {
        case .area:
            args.append("-i")
        case .window:
            args.append(contentsOf: ["-i", "-W"])
            if !Settings.windowShadow {
                args.append("-o")
            }
        case .screen:
            args.append("-m")
        }
        if !Settings.captureSound {
            args.append("-x")
        }
        args.append(url.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.isCapturing = false
                if FileManager.default.fileExists(atPath: url.path) {
                    completion(url)
                } else {
                    completion(nil) // annulé par l'utilisateur
                }
            }
        }
        do {
            try process.run()
        } catch {
            isCapturing = false
            NSLog("Cliche: impossible de lancer screencapture: %@", error.localizedDescription)
            completion(nil)
        }
    }

    static func newFileURL() -> URL {
        let dir = Settings.saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "yyyy-MM-dd 'à' HH.mm.ss"
        let name = "Capture \(formatter.string(from: Date())).png"
        return dir.appendingPathComponent(name)
    }
}

/// Réglages persistants (UserDefaults).
enum Settings {
    static let defaults: [String: Any] = [
        "autoCopy": true,
        "captureSound": true,
        "windowShadow": true,
        "quickActions": true,
    ]

    static var autoCopy: Bool {
        get { UserDefaults.standard.bool(forKey: "autoCopy") }
        set { UserDefaults.standard.set(newValue, forKey: "autoCopy") }
    }

    static var captureSound: Bool {
        get { UserDefaults.standard.bool(forKey: "captureSound") }
        set { UserDefaults.standard.set(newValue, forKey: "captureSound") }
    }

    static var windowShadow: Bool {
        get { UserDefaults.standard.bool(forKey: "windowShadow") }
        set { UserDefaults.standard.set(newValue, forKey: "windowShadow") }
    }

    static var quickActions: Bool {
        get { UserDefaults.standard.bool(forKey: "quickActions") }
        set { UserDefaults.standard.set(newValue, forKey: "quickActions") }
    }

    static var saveDirectory: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: "saveDir"), !path.isEmpty {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            }
            let pictures = FileManager.default.urls(
                for: .picturesDirectory, in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
            return pictures.appendingPathComponent("Cliché")
        }
        set { UserDefaults.standard.set(newValue.path, forKey: "saveDir") }
    }
}
