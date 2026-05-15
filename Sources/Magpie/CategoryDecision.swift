import Foundation

/// A decision about where a file should be filed, plus the rationale.
struct CategoryDecision: Hashable {
    enum Source: Hashable {
        case rule(id: UUID, pattern: String)
        case llm(model: String)

        var shortLabel: String {
            switch self {
            case .rule: return "Rule"
            case .llm:  return "AI"
            }
        }
    }

    let category: String
    let reason: String
    let source: Source
}
