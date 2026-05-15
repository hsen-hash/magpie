import Foundation

struct MagpieConfig {
    let provider: String
    let geminiApiKey: String
    let geminiModel: String
}

enum ConfigLoader {
    static var configURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/magpie/config.json")
    }

    static func load() -> MagpieConfig? {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let key = (json["geminiApiKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != "PASTE_YOUR_NEW_KEY_HERE" else { return nil }
        return MagpieConfig(
            provider: json["provider"] as? String ?? "gemini",
            geminiApiKey: key,
            geminiModel: (json["geminiModel"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "gemini-2.5-flash"
        )
    }
}
