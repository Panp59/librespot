import Foundation

struct DictationResponse: Decodable {
    let text: String
}

struct MeetingResponse: Decodable {
    let markdownPath: String
    let jsonPath: String
    let outputDir: String
    let numSegments: Int
    let speakers: [String]

    enum CodingKeys: String, CodingKey {
        case markdownPath = "markdown_path"
        case jsonPath = "json_path"
        case outputDir = "output_dir"
        case numSegments = "num_segments"
        case speakers
    }
}

/// Client HTTP vers le backend Python local (127.0.0.1:8765).
final class BackendClient {
    static let baseURL = URL(string: "http://127.0.0.1:8765")!

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // Une réunion d'une heure peut mettre plusieurs minutes à se traiter.
        config.timeoutIntervalForRequest = 7_200
        config.timeoutIntervalForResource = 7_200
        session = URLSession(configuration: config)
    }

    func health(_ completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 2
        session.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    /// `language` : nil = langue par défaut du backend ; "auto" = détection
    /// automatique ; sinon un code langue ("fr", "en"…).
    func dictate(audioURL: URL, language: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        var fields: [String: String] = [:]
        if let language { fields["language"] = language }
        upload(path: "dictate", files: [("audio", audioURL)], fields: fields) { (result: Result<DictationResponse, Error>) in
            completion(result.map { $0.text })
        }
    }

    func processMeeting(
        micURL: URL?,
        systemURL: URL?,
        mode: String,
        title: String,
        micOffset: Double = 0,
        systemOffset: Double = 0,
        completion: @escaping (Result<MeetingResponse, Error>) -> Void
    ) {
        var files: [(String, URL)] = []
        if let micURL { files.append(("mic", micURL)) }
        if let systemURL { files.append(("system", systemURL)) }
        let fields = [
            "mode": mode,
            "title": title,
            "mic_offset": String(format: "%.3f", micOffset),
            "system_offset": String(format: "%.3f", systemOffset),
        ]
        upload(path: "meeting", files: files, fields: fields, completion: completion)
    }

    // MARK: - Multipart

    /// Construit le corps multipart dans un fichier temporaire (les
    /// enregistrements de réunion peuvent faire des centaines de Mo) puis
    /// l'envoie avec un uploadTask.
    private func upload<T: Decodable>(
        path: String,
        files: [(name: String, url: URL)],
        fields: [String: String],
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        // La copie du corps multipart peut représenter des centaines de Mo
        // pour une réunion : tout se prépare hors du thread principal.
        DispatchQueue.global(qos: .utility).async {
            self.prepareAndSend(path: path, files: files, fields: fields, completion: completion)
        }
    }

    private func prepareAndSend<T: Decodable>(
        path: String,
        files: [(name: String, url: URL)],
        fields: [String: String],
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        let boundary = "murmure-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmure-upload-\(UUID().uuidString).tmp")

        do {
            try buildMultipartBody(to: bodyURL, boundary: boundary, files: files, fields: fields)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        session.uploadTask(with: request, fromFile: bodyURL) { data, response, error in
            defer { try? FileManager.default.removeItem(at: bodyURL) }
            let result: Result<T, Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let detail = data.flatMap { String(data: $0, encoding: .utf8) } ?? "(pas de détail)"
                result = .failure(NSError(
                    domain: "Murmure", code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Le backend a répondu \(http.statusCode) : \(detail)"]
                ))
            } else if let data {
                do {
                    result = .success(try JSONDecoder().decode(T.self, from: data))
                } catch {
                    result = .failure(error)
                }
            } else {
                result = .failure(NSError(
                    domain: "Murmure", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Réponse vide du backend."]
                ))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private func buildMultipartBody(
        to bodyURL: URL,
        boundary: String,
        files: [(name: String, url: URL)],
        fields: [String: String]
    ) throws {
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: bodyURL)
        defer { try? handle.close() }

        func write(_ string: String) throws {
            try handle.write(contentsOf: Data(string.utf8))
        }

        for (key, value) in fields {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            try write("\(value)\r\n")
        }

        for (name, fileURL) in files {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
            try write("Content-Type: application/octet-stream\r\n\r\n")
            // Copie par blocs de 4 Mo pour ne pas charger le fichier en mémoire.
            let input = try FileHandle(forReadingFrom: fileURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
            }
            try write("\r\n")
        }

        try write("--\(boundary)--\r\n")
    }
}
