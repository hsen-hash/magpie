import Foundation

/// How many files Magpie filed into a given category during the digest window.
struct DigestCategoryCount: Codable, Identifiable, Hashable {
    var id: String { category }
    let category: String
    let count: Int
}

/// A single notable file (largest add, big duplicate, etc.).
struct DigestFileRef: Codable, Identifiable, Hashable {
    var id: String { path }
    let path: String
    let bytes: Int64

    var name: String { (path as NSString).lastPathComponent }
}

/// A point-in-time summary of folder activity and clutter, produced by
/// `DigestService` either on the daily schedule or on demand.
struct DailyDigest: Codable, Hashable {
    let generatedAt: Date
    /// Start of the window this digest covers (usually the previous run).
    let periodStart: Date

    // What was added / organized
    let filesFiled: Int
    let bytesFiled: Int64
    let byCategory: [DigestCategoryCount]
    let largestNew: [DigestFileRef]

    // Clutter signals
    let stuckInRecents: Int
    let duplicateGroups: Int
    let reclaimableBytes: Int64

    /// Deterministic, local, always-present clutter tips.
    let tips: [String]
    /// Optional AI-written prose summary. `nil` when no provider is configured
    /// or the call failed (the heuristic tips still stand on their own).
    var narrative: String?
    /// Provider/model that wrote the narrative, for transparency.
    var narrativeModel: String?

    var hasActivity: Bool {
        filesFiled > 0 || stuckInRecents > 0 || duplicateGroups > 0
    }
}

extension Int64 {
    /// Human-readable byte count, e.g. "4.2 MB".
    var humanBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

/// Persists the latest digest + last-run timestamp under
/// `~/.config/magpie/`. Small enough to keep as plain JSON files.
struct DigestStore {
    private let digestURL: URL
    private let lastRunKey = "magpieDigestLastRun_v1"

    init() {
        digestURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/magpie/last_digest.json")
    }

    var lastRun: Date? {
        let t = UserDefaults.standard.double(forKey: lastRunKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    func load() -> DailyDigest? {
        guard let data = try? Data(contentsOf: digestURL) else { return nil }
        return try? JSONDecoder.digest.decode(DailyDigest.self, from: data)
    }

    func save(digest: DailyDigest, lastRun: Date) {
        if let data = try? JSONEncoder.digest.encode(digest) {
            try? FileManager.default.createDirectory(
                at: digestURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: digestURL)
        }
        UserDefaults.standard.set(lastRun.timeIntervalSince1970, forKey: lastRunKey)
    }
}

private extension JSONEncoder {
    static var digest: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted]
        return e
    }
}

private extension JSONDecoder {
    static var digest: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
