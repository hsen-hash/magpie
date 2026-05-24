import Foundation

struct MagpieConfig {
    /// Selected provider: "gemini" (cloud) or "ollama" (local).
    let provider: String

    // Gemini
    let geminiApiKey: String
    let geminiModel: String

    // Ollama (local, no key required)
    let ollamaHost: URL
    let ollamaModel: String
    /// How long Ollama should keep the model resident in RAM/VRAM after
    /// the last request. "10m" is a sane default — keeps repeat batches
    /// snappy without holding memory forever.
    let ollamaKeepAlive: String

    /// True when the config has whatever it needs for the chosen provider.
    /// (Gemini needs a key; Ollama is configurable but works out of the box.)
    var isUsable: Bool {
        switch provider.lowercased() {
        case "ollama":
            return !ollamaModel.isEmpty
        default:
            let k = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return !k.isEmpty && k != "PASTE_YOUR_NEW_KEY_HERE"
        }
    }
}

enum ConfigLoader {
    static var configURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/magpie/config.json")
    }

    static let defaultGeminiModel = "gemini-2.5-flash"
    static let defaultOllamaHost = URL(string: "http://localhost:11434")!
    static let defaultOllamaModel = "llama3.2"
    static let defaultOllamaKeepAlive = "10m"

    /// Returns a config object if one exists on disk AND is usable for its
    /// selected provider. Returns `nil` when the file is missing or when the
    /// active provider isn't configured (e.g. Gemini selected with no key).
    static func load() -> MagpieConfig? {
        let cfg = read()
        return cfg.isUsable ? cfg : nil
    }

    /// Always returns a config object — falling back to defaults for any
    /// fields not present in the file. Useful when callers need to know the
    /// selected provider even if it isn't fully usable yet.
    static func read() -> MagpieConfig {
        let json: [String: Any] = (try? Data(contentsOf: configURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            ?? [:]

        let provider = (json["provider"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "gemini"

        let geminiKey = (json["geminiApiKey"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let geminiModel = (json["geminiModel"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? defaultGeminiModel

        let hostString = (json["ollamaHost"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? defaultOllamaHost.absoluteString
        let ollamaHost = URL(string: hostString) ?? defaultOllamaHost
        let ollamaModel = (json["ollamaModel"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? defaultOllamaModel
        let keepAlive = (json["ollamaKeepAlive"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? defaultOllamaKeepAlive

        return MagpieConfig(
            provider: provider,
            geminiApiKey: geminiKey,
            geminiModel: geminiModel,
            ollamaHost: ollamaHost,
            ollamaModel: ollamaModel,
            ollamaKeepAlive: keepAlive
        )
    }

    /// Default config template written when the user first opens it from
    /// the popover. Documents both providers inline.
    static let defaultTemplate = """
    {
      "provider": "gemini",

      "geminiApiKey": "PASTE_YOUR_NEW_KEY_HERE",
      "geminiModel": "\(defaultGeminiModel)",

      "ollamaHost": "\(defaultOllamaHost.absoluteString)",
      "ollamaModel": "\(defaultOllamaModel)",
      "ollamaKeepAlive": "\(defaultOllamaKeepAlive)"
    }
    """
}
