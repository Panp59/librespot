import Foundation

/// Résumé de la journée par un LLM local via Ollama, comme les
/// comptes-rendus Murmure. Jamais bloquant : si Ollama est éteint,
/// le rapport reste complet, il manque juste la prose.
enum SummaryClient {
    static var model: String {
        ProcessInfo.processInfo.environment["SABLIER_OLLAMA_MODEL"] ?? "qwen3:14b"
    }

    static func summarize(
        day: String,
        lines: [String],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let prompt = """
        Tu es l'assistant d'un dirigeant de PME française. Voici le relevé \
        de son activité sur Mac pour la journée du \(day), agrégé par \
        catégorie puis par application (durées réelles, hors absences) :

        \(lines.joined(separator: "\n"))

        Rédige en français un court bilan de la journée (5 phrases maximum) : \
        où est passé le temps, le niveau de fragmentation, et une observation \
        utile ou un conseil concret. Ton direct et bienveillant, pas de flatterie. \
        N'utilise pas de tiret long. Réponds uniquement avec le bilan.
        """

        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "stream": false,
        ])

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      var response = json["response"] as? String else {
                    completion(.failure(NSError(
                        domain: "Sablier", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Réponse Ollama illisible"]
                    )))
                    return
                }
                // Certains modèles (qwen3...) préfixent leur raisonnement.
                if let range = response.range(of: "</think>") {
                    response = String(response[range.upperBound...])
                }
                completion(.success(response.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }.resume()
    }
}
