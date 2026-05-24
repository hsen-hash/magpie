import Foundation

/// Shared types and protocol for any LLM-backed categorizer.
/// Both `GeminiCategorizer` (cloud) and `OllamaCategorizer` (local) conform.

enum CategorizerError: LocalizedError {
    case http(Int, String)
    case invalidResponse(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "HTTP \(code): \(body.prefix(160))"
        case .invalidResponse(let body):
            return "Bad response: \(body.prefix(160))"
        case .connectionFailed(let detail):
            return "Connection failed: \(detail.prefix(160))"
        }
    }
}

struct CategorizerUsage {
    let promptTokens: Int
    let candidateTokens: Int
    let totalTokens: Int
    /// HTTP status code, or 0 when not applicable (e.g. local IPC errors).
    let httpStatus: Int
}

struct CategorizerDecision {
    let category: String
    let reason: String
}

struct CategorizerResult {
    let mapping: [String: CategorizerDecision]
    let usage: CategorizerUsage
    /// Concrete model string actually used (e.g. "gemini-2.5-flash" or "llama3.2").
    let model: String
}

/// Identifies the family of provider behind a categorizer, used by the
/// usage log and the UI to label / price each call correctly.
enum CategorizerProvider: String, Hashable {
    case gemini
    case ollama

    var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        }
    }

    /// Local providers never incur a per-call dollar cost.
    var isLocal: Bool {
        switch self {
        case .gemini: return false
        case .ollama: return true
        }
    }
}

/// Anything that can take a batch of filenames and return categories.
protocol Categorizer: Actor {
    /// Provider family (used for cost rules and UI badging).
    nonisolated var provider: CategorizerProvider { get }

    /// Human-readable display label (e.g. "Gemini · gemini-2.5-flash"
    /// or "Ollama · llama3.2 @ localhost:11434"). Surfaced in error banners.
    nonisolated var displayLabel: String { get }

    func categorize(filenames: [String],
                    existingCategories: [String]) async throws -> CategorizerResult
}

/// Shared prompt used by every categorizer. The wording was tuned on Gemini
/// Flash and works well for instruction-tuned Llama / Qwen / Mistral models
/// when paired with a JSON-only output mode.
enum CategorizerPrompt {
    static func build(filenames: [String], existing: [String]) -> String {
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

    /// Convert a raw `{filename: {category, why}}` dictionary into typed decisions.
    /// Accepts both the canonical shape and the legacy "filename → category string" shape.
    static func parse(raw: [String: Any]) -> [String: CategorizerDecision] {
        var map: [String: CategorizerDecision] = [:]
        for (filename, value) in raw {
            if let dict = value as? [String: Any],
               let cat = dict["category"] as? String, !cat.isEmpty {
                let why = (dict["why"] as? String) ?? ""
                map[filename] = CategorizerDecision(category: cat, reason: why)
            } else if let cat = value as? String, !cat.isEmpty {
                // Backwards-compat: model returned plain "category" strings.
                map[filename] = CategorizerDecision(category: cat, reason: "")
            }
        }
        return map
    }
}
