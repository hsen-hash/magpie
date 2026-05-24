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
        /// The active provider isn't configured (e.g. Gemini chosen without
        /// a key). The popover surfaces a "Set up <provider>…" button.
        case notConfigured(provider: CategorizerProvider)
        case working
        case error(String)
    }

    @Published private(set) var categories: [URL: CategoryDecision] = [:]
    @Published private(set) var status: Status
    /// Active provider for the current run. UI labels (banner copy, dashboard
    /// title) pull from this so we never hard-code "Gemini" in user-facing
    /// strings.
    @Published private(set) var activeProvider: CategorizerProvider

    let apiLog: ApiUsageLog
    let rulesStore: RulesStore
    private let store: WatchedFoldersStore
    private let categorizer: (any Categorizer)?
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

        // Read whatever's on disk so we know which provider the user picked,
        // then only construct the categorizer if it's actually usable.
        let cfg = ConfigLoader.read()
        let provider = CategorizerProvider(rawValue: cfg.provider.lowercased()) ?? .gemini
        self.activeProvider = provider

        if cfg.isUsable {
            switch provider {
            case .gemini:
                self.categorizer = GeminiCategorizer(config: cfg)
            case .ollama:
                self.categorizer = OllamaCategorizer(config: cfg)
            }
            self.status = .idle
        } else {
            self.categorizer = nil
            self.status = .notConfigured(provider: provider)
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

            // Rules apply before the LLM. First match wins; saves a model call.
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

        // Rule-matched files already filed above. Everything left needs the LLM —
        // bail if it isn't configured.
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
                    provider: categorizer.provider.rawValue,
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
        categorizer: any Categorizer,
        filenames: [String],
        existing: [String]
    ) async throws -> CategorizerResult {
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
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? ConfigLoader.defaultTemplate.data(using: .utf8)?.write(to: url)
        }
        NSWorkspace.shared.open(url)
    }
}
