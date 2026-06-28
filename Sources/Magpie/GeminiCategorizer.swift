import Foundation

actor GeminiCategorizer: Categorizer {
    nonisolated let provider: CategorizerProvider = .gemini
    nonisolated let displayLabel: String

    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(config: MagpieConfig) {
        self.apiKey = config.geminiApiKey
        self.model = config.geminiModel
        self.displayLabel = "Gemini · \(config.geminiModel)"
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: cfg)
    }

    /// Strip query string from a URL so a leaked API key never lands in logs.
    private static func sanitize(_ raw: String) -> String {
        guard let i = raw.firstIndex(of: "?") else { return raw }
        return String(raw[..<i]) + "?key=REDACTED"
    }

    func categorize(filenames: [String], existingCategories: [String]) async throws -> CategorizerResult {
        guard !filenames.isEmpty else {
            return CategorizerResult(
                mapping: [:],
                usage: CategorizerUsage(promptTokens: 0, candidateTokens: 0, totalTokens: 0, httpStatus: 0),
                model: model
            )
        }

        let prompt = CategorizerPrompt.build(filenames: filenames, existing: existingCategories)
        let endpoint = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        )!

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Send key in a header so the URL stays clean of secrets in any error log.
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.0,
                "responseMimeType": "application/json"
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // URLSession wraps the full URL in its NSError description.
            // Rewrite the error so any leaked API key in the URL is redacted.
            let safe = Self.sanitize(error.localizedDescription)
            throw CategorizerError.invalidResponse(safe)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CategorizerError.invalidResponse("no HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? "<binary>"
            throw CategorizerError.http(http.statusCode, snippet)
        }

        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = envelope?["candidates"] as? [[String: Any]]
        let parts = (candidates?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
        let text = (parts?.first?["text"] as? String) ?? ""

        guard let inner = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: inner) as? [String: Any] else {
            throw CategorizerError.invalidResponse(text)
        }

        let map = CategorizerPrompt.parse(raw: raw)

        let usageDict = envelope?["usageMetadata"] as? [String: Any]
        let usage = CategorizerUsage(
            promptTokens: (usageDict?["promptTokenCount"] as? Int) ?? 0,
            candidateTokens: (usageDict?["candidatesTokenCount"] as? Int) ?? 0,
            totalTokens: (usageDict?["totalTokenCount"] as? Int) ?? 0,
            httpStatus: http.statusCode
        )

        return CategorizerResult(mapping: map, usage: usage, model: model)
    }
}

extension GeminiCategorizer: TextCompleter {
    /// Freeform completion used by the daily digest. Unlike `categorize`, this
    /// asks for plain prose (no JSON response mode) and uses a small non-zero
    /// temperature so the summary reads naturally.
    func complete(prompt: String) async throws -> CompletionResult {
        let endpoint = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        )!

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.4]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw CategorizerError.invalidResponse(Self.sanitize(error.localizedDescription))
        }
        guard let http = response as? HTTPURLResponse else {
            throw CategorizerError.invalidResponse("no HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? "<binary>"
            throw CategorizerError.http(http.statusCode, snippet)
        }

        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = envelope?["candidates"] as? [[String: Any]]
        let parts = (candidates?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
        let text = ((parts?.first?["text"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let usageDict = envelope?["usageMetadata"] as? [String: Any]
        let usage = CategorizerUsage(
            promptTokens: (usageDict?["promptTokenCount"] as? Int) ?? 0,
            candidateTokens: (usageDict?["candidatesTokenCount"] as? Int) ?? 0,
            totalTokens: (usageDict?["totalTokenCount"] as? Int) ?? 0,
            httpStatus: http.statusCode
        )
        return CompletionResult(text: text, usage: usage, model: model)
    }
}
