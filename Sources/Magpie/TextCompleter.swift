import Foundation

/// Result of a freeform text completion. Mirrors `CategorizerResult` so the
/// same usage-logging path (tokens in/out, cost) applies to digest narratives.
struct CompletionResult {
    let text: String
    let usage: CategorizerUsage
    let model: String
}

/// Anything that can turn a freeform prompt into text. Implemented by the same
/// actors that back categorization (`GeminiCategorizer`, `OllamaCategorizer`),
/// so the daily digest reuses whichever provider the user already configured —
/// no new keys, no new setup, and Ollama stays fully local / free.
protocol TextCompleter {
    func complete(prompt: String) async throws -> CompletionResult
}
