import Foundation
import Network

/// Petite API HTTP locale pour piloter Clap depuis un CLI (Claude Code, curl).
/// Écoute UNIQUEMENT sur 127.0.0.1, éteinte par défaut, protégée par un
/// jeton écrit dans ~/Library/Application Support/Clap/control.json.
///
/// Points d'entrée :
///   GET  /health          -> {"ok":true} (sans jeton, pour tester la vie)
///   GET  /status          -> {"recording":bool,"session":path?,"elapsed":s}
///   POST /start  body JSON {"target":"screen"|"window","match":"OPTIMa","webcam":false}
///   POST /stop            -> {"ok":true,"session":path}
protocol ControlServerDelegate: AnyObject {
    func controlStart(
        target: String, match: String?, webcam: Bool,
        completion: @escaping (Result<String, String>) -> Void
    )
    func controlStop(completion: @escaping (Result<String, String>) -> Void)
    func controlStatus() -> [String: Any]
}

final class ControlServer {
    static let port: UInt16 = 8787

    weak var delegate: ControlServerDelegate?
    private(set) var isRunning = false
    private(set) var token = ""

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "fr.adti.clap.control")

    static var infoFileURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("control.json")
    }

    func start() throws {
        guard !isRunning else { return }
        token = UUID().uuidString

        let params = NWParameters.tcp
        // Bind loopback strict : injoignable depuis le réseau.
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .init(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.stop() }
        }
        listener.start(queue: queue)
        self.listener = listener
        isRunning = true

        let info: [String: Any] = ["port": Int(Self.port), "token": token]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: .prettyPrinted) {
            try? data.write(to: Self.infoFileURL)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        try? FileManager.default.removeItem(at: Self.infoFileURL)
    }

    // MARK: - Connexion

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            let separator = Data("\r\n\r\n".utf8)
            if let range = buffer.range(of: separator) {
                let headerData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                let header = String(decoding: headerData, as: UTF8.self)
                let contentLength = Self.contentLength(in: header)
                let bodyStart = range.upperBound
                let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
                if available >= contentLength {
                    let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
                    let body = buffer.subdata(in: bodyStart..<bodyEnd)
                    self.handle(connection, header: header, body: body)
                } else {
                    self.receive(connection, buffer: buffer) // corps incomplet
                }
            } else if error == nil, !isComplete {
                self.receive(connection, buffer: buffer) // en-têtes incomplets
            } else {
                connection.cancel()
            }
        }
    }

    private func handle(_ connection: NWConnection, header: String, body: Data) {
        let lines = header.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { respond(connection, status: "400 Bad Request", json: ["ok": false]); return }
        let method = parts[0].uppercased()
        let path = parts[1]

        // /health répond sans jeton (test de vie).
        if method == "GET", path == "/health" {
            respond(connection, json: ["ok": true, "app": "Clap"])
            return
        }

        // Défense simple : une page web qui tenterait un fetch enverrait un
        // en-tête Origin. Le CLI n'en envoie pas.
        if headerValue(lines, "origin") != nil {
            respond(connection, status: "403 Forbidden", json: ["ok": false, "error": "origine refusée"])
            return
        }

        // Toutes les autres routes exigent le bon jeton.
        guard headerValue(lines, "x-clap-token") == token, !token.isEmpty else {
            respond(connection, status: "401 Unauthorized", json: ["ok": false, "error": "jeton invalide"])
            return
        }

        switch (method, path) {
        case ("GET", "/status"):
            DispatchQueue.main.async {
                let status = self.delegate?.controlStatus() ?? [:]
                self.respond(connection, json: status)
            }

        case ("POST", "/start"):
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            let target = (json["target"] as? String) ?? "screen"
            let match = json["match"] as? String
            let webcam = (json["webcam"] as? Bool) ?? false
            DispatchQueue.main.async {
                self.delegate?.controlStart(target: target, match: match, webcam: webcam) { result in
                    self.respondResult(connection, result)
                }
            }

        case ("POST", "/stop"):
            DispatchQueue.main.async {
                self.delegate?.controlStop { result in
                    self.respondResult(connection, result)
                }
            }

        default:
            respond(connection, status: "404 Not Found", json: ["ok": false, "error": "route inconnue"])
        }
    }

    private func respondResult(_ connection: NWConnection, _ result: Result<String, String>) {
        switch result {
        case .success(let session):
            respond(connection, json: ["ok": true, "session": session])
        case .failure(let message):
            respond(connection, status: "409 Conflict", json: ["ok": false, "error": message])
        }
    }

    private func respond(_ connection: NWConnection, status: String = "200 OK", json: [String: Any]) {
        let bodyData = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(bodyData.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(bodyData)
        connection.send(content: out, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Analyse d'en-têtes

    private static func contentLength(in header: String) -> Int {
        for line in header.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    private func headerValue(_ lines: [String], _ name: String) -> String? {
        let prefix = name.lowercased() + ":"
        for line in lines where line.lowercased().hasPrefix(prefix) {
            return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
