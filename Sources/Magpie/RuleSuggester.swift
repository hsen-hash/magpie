import Foundation

/// Heuristically derive a glob pattern from a filename. The suggestion is shown
/// to the user in a confirmation sheet — they can edit it before saving.
///
/// Strategy: keep alphabetic "stems" intact; replace anything that looks variable
/// (dates, timestamps, UUIDs, long hex blobs, digit runs) with `*`. Then collapse
/// runs of separators around the wildcards.
enum RuleSuggester {
    static func suggest(filename: String) -> String {
        let ns = filename as NSString
        let stem = ns.deletingPathExtension
        let ext = ns.pathExtension.lowercased()

        var working = stem
        for (regex, replacement) in Self.replacements {
            working = working.replacingOccurrences(
                of: regex,
                with: replacement,
                options: .regularExpression
            )
        }

        // Collapse "* shortword *" — small connective tokens like "at", "de", "le"
        // stuck between wildcards. Run twice to handle "* a * b *" → "*".
        for _ in 0..<2 {
            working = working.replacingOccurrences(
                of: #"\*[\s_\-.]+\S{1,6}[\s_\-.]+\*"#,
                with: "*",
                options: .regularExpression
            )
        }

        // Collapse "x_*_-_*_y" → "x_*_y" so we don't end up with separator soup.
        working = working.replacingOccurrences(
            of: #"([\s_\-.])+\*+([\s_\-.])+"#,
            with: "$1*$2",
            options: .regularExpression
        )

        // Collapse runs of stars to one.
        working = working.replacingOccurrences(
            of: #"\*+"#,
            with: "*",
            options: .regularExpression
        )

        // Trim trailing/leading separators (but leave a leading `*` if present).
        working = working.trimmingCharacters(in: CharacterSet(charactersIn: " _-."))

        if working.isEmpty { working = "*" }

        return ext.isEmpty ? working : "\(working).\(ext)"
    }

    /// Ordered: more specific patterns first.
    private static let replacements: [(String, String)] = [
        // UUID (8-4-4-4-12)
        (#"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#, "*"),
        // ISO-ish dates: 2026-05-15, 2026_05_15, 2026.05.15, 2026/05/15
        (#"\d{4}[-_./]\d{2}[-_./]\d{2}"#, "*"),
        // Reversed: 15-05-2026 etc.
        (#"\d{2}[-_./]\d{2}[-_./]\d{4}"#, "*"),
        // Timestamps: 10.34.21, 10:34, 10h34
        (#"\d{1,2}[.:h]\d{2}([.:h]\d{2})?"#, "*"),
        // Long hex blob (8+) — likely hash / id
        (#"\b[0-9a-fA-F]{8,}\b"#, "*"),
        // Generic 3+ digit runs (counters, years)
        (#"\d{3,}"#, "*"),
    ]
}
