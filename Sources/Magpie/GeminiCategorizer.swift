import Foundation

actor GeminiCategorizer {
    enum CategorizerError: LocalizedError {
        case http(Int, String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "HTTP \(code): \(body.prefix(160))"
            case .invalidResponse(let body): return "Bad response: \(body.prefix(160))"
            }
        }
    }

    struct Usage {
        let promptTokens: Int
        let candidateTokens: Int
        let totalTokens: Int
        let httpStatus: Int
    }

    struct Decision {
        let category: String
        let reason: String
    }

    struct Result {
        let mapping: [String: Decision]
        let usage: Usage
        let model: String
    }

    private let config: MagpieConfig
    private let session: URLSession

    init(config: MagpieConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: cfg)
    }

    /// Strip query string from a URL so a leaked API key never lands in logs.
    private static func sanitize(_ raw: String) -> String {
        guard let i = raw.firstIndex(of: "?") else { return raw }
        return String(raw[..<i]) + "?key=REDACTED"
    }

    func categorize(filenames: [String], existingCategories: [String]) async throws -> Result {
        guard !filenames.isEmpty else {
            return Result(
                mapping: [:],
                usage: Usage(promptTokens: 0, candidateTokens: 0, totalTokens: 0, httpStatus: 0),
                model: config.geminiModel
            )
        }

        let prompt = Self.buildPrompt(filenames: filenames, existing: existingCategories)
        let endpoint = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(config.geminiModel):generateContent"
        )!

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Send key in a header so the URL stays clean of secrets in any error log.
        req.setValue(config.geminiApiKey, forHTTPHeaderField: "x-goog-api-key")

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

        var map: [String: Decision] = [:]
        for (filename, value) in raw {
            if let dict = value as? [String: Any],
               let cat = dict["category"] as? String, !cat.isEmpty {
                let why = (dict["why"] as? String) ?? ""
                map[filename] = Decision(category: cat, reason: why)
            } else if let cat = value as? String, !cat.isEmpty {
                // Backwards-compat: model returned plain "category" strings.
                map[filename] = Decision(category: cat, reason: "")
            }
        }

        let usageDict = envelope?["usageMetadata"] as? [String: Any]
        let usage = Usage(
            promptTokens: (usageDict?["promptTokenCount"] as? Int) ?? 0,
            candidateTokens: (usageDict?["candidatesTokenCount"] as? Int) ?? 0,
            totalTokens: (usageDict?["totalTokenCount"] as? Int) ?? 0,
            httpStatus: http.statusCode
        )

        return Result(mapping: map, usage: usage, model: config.geminiModel)
    }

    private static func buildPrompt(filenames: [String], existing: [String]) -> String {
        let filenamesJSON = (try? String(
            data: JSONSerialization.data(withJSONObject: filenames),
            encoding: .utf8
        )) ?? "[]"
        let existingList = existing.isEmpty ? "(none yet)" : existing.joined(separator: ", ")

        return """
        You categorize filenames into broad folder categories for a personal file organizer.

        Existing categories the user already has: \(existingList)
        Prefer to reuse an existing category when appropriate. If a filename doesn't fit any, create a new short category (1–3 words, Title Case, human-readable, no emoji, no punctuation other than spaces).

        Examples of good categories: Screenshots, Receipts, Design Assets, Financial, Invoices, Resumes, Photos, Software, Documents, Code, Music, Videos, Books.

        Filenames to categorize:
        \(filenamesJSON)

        Return ONLY a JSON object mapping each input filename (verbatim) to an object with TWO fields:
          - "category": the chosen category string
          - "why": one short sentence (max 80 chars) citing the SPECIFIC clue in the filename that justified the choice. No filler. No restating the category.

        Example output:
        {
          "Invoice-2024-01.pdf": { "category": "Invoices", "why": "Filename starts with 'Invoice-' and is a PDF." },
          "IMG_8821.jpeg": { "category": "Photos", "why": "Standard camera 'IMG_####.jpeg' naming." }
        }

        Output ONLY the JSON object. No prose, no markdown, no code fences.
        """
    }
}
