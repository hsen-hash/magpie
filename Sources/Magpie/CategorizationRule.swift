import Foundation

struct CategorizationRule: Identifiable, Codable, Hashable {
    enum MatchType: String, Codable, CaseIterable, Identifiable {
        case glob
        case regex
        var id: String { rawValue }
        var label: String { self == .glob ? "Glob" : "Regex" }
    }

    var id: UUID = UUID()
    var pattern: String
    var matchType: MatchType
    var category: String
    var enabled: Bool = true

    func matches(filename: String) -> Bool {
        guard enabled, !pattern.isEmpty else { return false }
        switch matchType {
        case .glob:
            // NSPredicate LIKE supports glob-style `*` and `?` with [c] for case-insensitive.
            let p = NSPredicate(format: "SELF LIKE[c] %@", pattern)
            return p.evaluate(with: filename)
        case .regex:
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { return false }
            let range = NSRange(filename.startIndex..., in: filename)
            return regex.firstMatch(in: filename, range: range) != nil
        }
    }

    static func validate(pattern: String, matchType: MatchType) -> String? {
        if pattern.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Pattern is empty"
        }
        if matchType == .regex {
            do {
                _ = try NSRegularExpression(pattern: pattern, options: [])
            } catch {
                return "Invalid regex: \(error.localizedDescription)"
            }
        }
        return nil
    }
}
