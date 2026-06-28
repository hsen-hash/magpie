import Foundation

/// Fully local categorizer that talks to a self-hosted Ollama server
/// (https://ollama.com). No data leaves the machine.
///
/// Default endpoint is `http://localhost:11434`. The model is whichever
/// instruction-tuned model the user has pulled — e.g. `llama3.2`, `qwen2.5:3b`,
/// `mistral`, `phi3`, etc. Anything that responds well to `format: "json"`
/// works; small (~3B) instruct models are plenty for filename categorization.
actor OllamaCategorizer: Categorizer, TextCompleter {
    nonisolated let provider: CategorizerProvider = .ollama
    nonisolated let displayLabel: String

    private let host: URL
    private let model: String
    private let keepAlive: String
    private let session: URLSession

    init(config: MagpieConfig) {
        self.host = config.ollamaHost
        self.model = config.ollamaModel
        self.keepAlive = config.ollamaKeepAlive
        let hostLabel = config.ollamaHost.host
            .map { "\($0)\(config.ollamaHost.port.map { ":\($0)" } ?? "")" }
            ?? config.ollamaHost.absoluteString
        self.displayLabel = "Ollama · \(config.ollamaModel) @ \(hostLabel)"

        let cfg = URLSessionConfiguration.default
        // First generation after Ollama loads a model into VRAM can take a
        // while — especially on a cold machine. Be generous.
        cfg.timeoutIntervalForRequest = 180
        cfg.timeoutIntervalForResource = 240
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
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
        let endpoint = host.appendingPathComponent("api/generate")

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Ollama returns valid JSON in the `response` field when format="json"
        // is set. `stream: false` collapses the response into a single chunk
        // so we can decode it the same way as Gemini's structured output.
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "format": "json",
            "keep_alive": keepAlive,
            "options": [
                "temperature": 0.0,
                // Filename batches at chunk size 40 push past the default 2k
                // context. Give the model headroom so it doesn't silently
                // truncate either the prompt or its own answer.
                "num_ctx": 8192,
                "num_predict": 2048
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // The most common failure is "ollama isn't running" — surface a
            // tailored message so the user knows to `ollama serve` (or open
            // the Ollama.app menubar icon).
            let urlErr = error as? URLError
            let isConnFailure = urlErr.map {
                [.cannotConnectToHost, .cannotFindHost,
                 .networkConnectionLost, .notConnectedToInternet,
                 .timedOut].contains($0.code)
            } ?? false
            if isConnFailure {
                let label = host.host.map { "\($0):\(host.port ?? 11434)" } ?? host.absoluteString
                throw CategorizerError.connectionFailed(
                    "Couldn't reach Ollama at \(label). Is `ollama serve` running and is the model pulled?"
                )
            }
            throw CategorizerError.invalidResponse(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CategorizerError.invalidResponse("no HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? "<binary>"
            // 404 from Ollama almost always means the model isn't pulled yet.
            if http.statusCode == 404 {
                throw CategorizerError.http(404,
                    "Model '\(model)' not found on Ollama. Run: ollama pull \(model)")
            }
            throw CategorizerError.http(http.statusCode, snippet)
        }

        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let inner = (envelope?["response"] as? String) ?? ""

        // Some smaller models occasionally wrap their JSON in code fences
        // despite the format directive — strip them defensively.
        let cleaned = Self.stripCodeFences(inner)

        guard let innerData = cleaned.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any] else {
            throw CategorizerError.invalidResponse(inner)
        }

        let map = CategorizerPrompt.parse(raw: raw)

        // Ollama's token counts use different field names than Gemini.
        let promptTokens = (envelope?["prompt_eval_count"] as? Int) ?? 0
        let outputTokens = (envelope?["eval_count"] as? Int) ?? 0
        let usage = CategorizerUsage(
            promptTokens: promptTokens,
            candidateTokens: outputTokens,
            totalTokens: promptTokens + outputTokens,
            httpStatus: http.statusCode
        )

        return CategorizerResult(mapping: map, usage: usage, model: model)
    }

    /// Freeform completion used by the daily digest. Plain-text mode (no
    /// `format: "json"`), small temperature for a natural-sounding summary.
    /// Runs entirely on the local Ollama server — no data leaves the machine.
    func complete(prompt: String) async throws -> CompletionResult {
        let endpoint = host.appendingPathComponent("api/generate")

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "keep_alive": keepAlive,
            "options": [
                "temperature": 0.4,
                "num_ctx": 8192,
                "num_predict": 512
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            let urlErr = error as? URLError
            let isConnFailure = urlErr.map {
                [.cannotConnectToHost, .cannotFindHost,
                 .networkConnectionLost, .notConnectedToInternet,
                 .timedOut].contains($0.code)
            } ?? false
            if isConnFailure {
                let label = host.host.map { "\($0):\(host.port ?? 11434)" } ?? host.absoluteString
                throw CategorizerError.connectionFailed(
                    "Couldn't reach Ollama at \(label). Is `ollama serve` running and is the model pulled?"
                )
            }
            throw CategorizerError.invalidResponse(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CategorizerError.invalidResponse("no HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? "<binary>"
            if http.statusCode == 404 {
                throw CategorizerError.http(404,
                    "Model '\(model)' not found on Ollama. Run: ollama pull \(model)")
            }
            throw CategorizerError.http(http.statusCode, snippet)
        }

        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = ((envelope?["response"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let promptTokens = (envelope?["prompt_eval_count"] as? Int) ?? 0
        let outputTokens = (envelope?["eval_count"] as? Int) ?? 0
        let usage = CategorizerUsage(
            promptTokens: promptTokens,
            candidateTokens: outputTokens,
            totalTokens: promptTokens + outputTokens,
            httpStatus: http.statusCode
        )
        return CompletionResult(text: text, usage: usage, model: model)
    }

    /// Removes leading/trailing ```json fences if a chatty model added them.
    private static func stripCodeFences(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // Drop the opening fence (with optional language tag) up to the
            // first newline, then drop the trailing fence.
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3))
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
