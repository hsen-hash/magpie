import Foundation
import Combine
import AppKit

extension Notification.Name {
    static let magpieApiUsageDidChange = Notification.Name("magpieApiUsageDidChange")
}

@MainActor
final class CategorizationCoordinator: ObservableObject {
    enum Status: Equatable {
        case idle
        case missingKey
        case working
        case error(String)
    }

    @Published private(set) var categories: [URL: CategoryDecision] = [:]
    @Published private(set) var status: Status

    let apiLog: ApiUsageLog
    let rulesStore: RulesStore
    private let store: WatchedFoldersStore
    private let categorizer: GeminiCategorizer?
    private var cancellable: AnyCancellable?
    private var pending: Set<URL> = []
    private var batchTask: Task<Void, Never>?

    init(watcher: FileWatcherManager, store: WatchedFoldersStore, rulesStore: RulesStore) {
        self.store = store
        self.rulesStore = rulesStore
        let logPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/magpie/moves.sqlite")
        self.apiLog = ApiUsageLog(path: logPath)
        if let cfg = ConfigLoader.load() {
            self.categorizer = GeminiCategorizer(config: cfg)
            self.status = .idle
        } else {
            self.categorizer = nil
            self.status = .missingKey
        }

        cancellable = watcher.newDetectionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detections in
                self?.enqueueNew(detections)
            }
    }

    private func enqueueNew(_ detections: [FileWatcherManager.Detection]) {
        var candidates: [URL] = []
        for d in detections {
            let url = d.url
            guard categories[url] == nil, !pending.contains(url) else { continue }

            // Rules apply before the API. First match wins; saves a Gemini call.
            if let rule = rulesStore.matchRule(for: url.lastPathComponent) {
                let decision = CategoryDecision(
                    category: rule.category,
                    reason: "Matched rule: `\(rule.pattern)` (\(rule.matchType.label))",
                    source: .rule(id: rule.id, pattern: rule.pattern)
                )
                categories[url] = decision
                NSLog("Magpie: rule-matched '\(url.lastPathComponent)' → '\(rule.category)'")
                continue
            }

            candidates.append(url)
        }

        // If no API key, we still want rule-matched files filed (handled above).
        // Anything left goes to Gemini — bail if we can't call it.
        guard categorizer != nil else { return }
        guard !candidates.isEmpty else { return }
        for u in candidates { pending.insert(u) }
        scheduleBatch()
    }

    private func scheduleBatch() {
        batchTask?.cancel()
        batchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            await self?.flush()
        }
    }

    private let chunkSize = 40

    private func flush() async {
        guard let categorizer, !pending.isEmpty else { return }
        let snapshot = Array(pending)
        pending.removeAll()
        status = .working

        let existing = currentAILibraryCategories()
        var processed = 0
        var hardFailures: [URL] = []

        for chunk in stride(from: 0, to: snapshot.count, by: chunkSize).map({
            Array(snapshot[$0 ..< min($0 + chunkSize, snapshot.count)])
        }) {
            let filenames = chunk.map { $0.lastPathComponent }
            do {
                let result = try await categorizeWithRetry(
                    categorizer: categorizer,
                    filenames: filenames,
                    existing: existing
                )
                apiLog.record(
                    model: result.model,
                    filenameCount: filenames.count,
                    promptTokens: result.usage.promptTokens,
                    candidateTokens: result.usage.candidateTokens,
                    totalTokens: result.usage.totalTokens,
                    httpStatus: result.usage.httpStatus
                )
                for url in chunk {
                    if let dec = result.mapping[url.lastPathComponent], !dec.category.isEmpty {
                        let reason = dec.reason.isEmpty
                            ? "Categorized by \(result.model)."
                            : dec.reason
                        categories[url] = CategoryDecision(
                            category: dec.category,
                            reason: reason,
                            source: .llm(model: result.model)
                        )
                        NSLog("Magpie: categorized '\(url.lastPathComponent)' → '\(dec.category)' (\(reason))")
                        processed += 1
                    } else {
                        hardFailures.append(url)
                    }
                }
                NotificationCenter.default.post(name: .magpieApiUsageDidChange, object: nil)
            } catch {
                NSLog("Magpie: chunk failed after retry: \(error.localizedDescription)")
                // Put this chunk back in pending so the next flush picks it up.
                for u in chunk { pending.insert(u) }
                status = .error(error.localizedDescription)
                // Stop processing further chunks — the user will see the error and can retry.
                return
            }
        }

        NSLog("Magpie: flush summary — categorized \(processed), unmatched in response: \(hardFailures.count)")
        status = .idle
    }

    private func categorizeWithRetry(
        categorizer: GeminiCategorizer,
        filenames: [String],
        existing: [String]
    ) async throws -> GeminiCategorizer.Result {
        do {
            return try await categorizer.categorize(filenames: filenames, existingCategories: existing)
        } catch {
            NSLog("Magpie: chunk first attempt failed (\(filenames.count) files), retrying once…")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return try await categorizer.categorize(filenames: filenames, existingCategories: existing)
        }
    }

    private func currentAILibraryCategories() -> [String] {
        let fm = FileManager.default
        var result: Set<String> = []
        for parent in store.folders {
            let aiLib = ManagedFolder.aiLibrary.url(in: parent)
            guard let contents = try? fm.contentsOfDirectory(atPath: aiLib.path) else { continue }
            for name in contents where !name.hasPrefix(".") {
                let url = aiLib.appendingPathComponent(name)
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if isDir { result.insert(name) }
            }
        }
        return Array(result).sorted()
    }

    func openConfigInEditor() {
        let url = ConfigLoader.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            let template = """
            {
              "provider": "gemini",
              "geminiApiKey": "PASTE_YOUR_NEW_KEY_HERE",
              "geminiModel": "gemini-2.5-flash"
            }
            """
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? template.data(using: .utf8)?.write(to: url)
        }
        NSWorkspace.shared.open(url)
    }
}
