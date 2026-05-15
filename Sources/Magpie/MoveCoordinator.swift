import Foundation
import Combine
import AppKit

@MainActor
final class MoveCoordinator: ObservableObject {
    @Published private(set) var recentMoves: [MoveRecord] = []
    /// Final resting place for files keyed by their original detection URL.
    /// Lets the UI show "→ AI Library/Receipts/foo.pdf".
    @Published private(set) var finalLocations: [URL: URL] = [:]

    private let store: WatchedFoldersStore
    private let watcher: FileWatcherManager
    private let categorizer: CategorizationCoordinator
    let log: MoveLog

    /// Tracks files staged in Recents but not yet filed by category.
    /// Key = original detected URL, Value = current location (in Recents).
    private var staged: [URL: URL] = [:]
    private var detectionCancellable: AnyCancellable?
    private var categoryCancellable: AnyCancellable?

    init(store: WatchedFoldersStore,
         watcher: FileWatcherManager,
         categorizer: CategorizationCoordinator) {
        self.store = store
        self.watcher = watcher
        self.categorizer = categorizer

        let logPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/magpie/moves.sqlite")
        self.log = MoveLog(path: logPath)
        self.recentMoves = log.recent(limit: 30)

        detectionCancellable = watcher.newDetectionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detections in
                self?.handleDetections(detections)
            }

        categoryCancellable = categorizer.$categories
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cats in
                self?.handleCategories(cats)
            }
    }

    private func handleDetections(_ detections: [FileWatcherManager.Detection]) {
        for d in detections {
            guard staged[d.url] == nil, finalLocations[d.url] == nil else { continue }
            stageToRecents(d.url)
        }
    }

    private func stageToRecents(_ original: URL) {
        guard let parent = watchedParent(of: original) else { return }
        guard FileManager.default.fileExists(atPath: original.path) else { return }
        let recents = ManagedFolder.recents.url(in: parent)
        do {
            let dest = try FileMover.move(from: original, intoDirectory: recents)
            staged[original] = dest
            // Don't log staging — only the final move (origin → AI Library) is user-visible.
            NSLog("Magpie: staged → \(dest.path)")
        } catch {
            NSLog("Magpie: stage move failed for \(original.path): \(error.localizedDescription)")
        }
    }

    private func handleCategories(_ cats: [URL: CategoryDecision]) {
        for (originalURL, decision) in cats {
            guard finalLocations[originalURL] == nil else { continue }
            guard let stagedURL = staged[originalURL] else { continue }
            guard FileManager.default.fileExists(atPath: stagedURL.path) else {
                staged.removeValue(forKey: originalURL)
                continue
            }
            fileToCategory(stagedURL: stagedURL, originalURL: originalURL, decision: decision)
        }
    }

    private func fileToCategory(stagedURL: URL, originalURL: URL, decision: CategoryDecision) {
        guard let parent = watchedParent(of: originalURL) else { return }
        let folderName = FileMover.sanitizeFolderName(decision.category)
        let destDir = ManagedFolder.aiLibrary.url(in: parent)
            .appendingPathComponent(folderName, isDirectory: true)
        let sourceKind: String
        switch decision.source {
        case .rule: sourceKind = "rule"
        case .llm:  sourceKind = "llm"
        }
        do {
            let dest = try FileMover.move(from: stagedURL, intoDirectory: destDir)
            // Log the full journey + the reason behind it.
            log.record(
                from: originalURL,
                to: dest,
                reason: decision.reason,
                sourceKind: sourceKind
            )
            staged.removeValue(forKey: originalURL)
            finalLocations[originalURL] = dest
            refreshRecent()
            NSLog("Magpie: filed → \(dest.path)")
        } catch {
            NSLog("Magpie: file move failed for \(stagedURL.path): \(error.localizedDescription)")
        }
    }

    /// Move a filed file back to its original location.
    /// Tells the watcher to suppress the resulting detection so we don't loop.
    func revert(_ record: MoveRecord) {
        let from = URL(fileURLWithPath: record.newPath)
        let to = URL(fileURLWithPath: record.originalPath)
        guard FileManager.default.fileExists(atPath: from.path) else {
            NSLog("Magpie: revert: source missing \(from.path)")
            return
        }
        let destDir = to.deletingLastPathComponent()
        watcher.suppressDetection(of: to.lastPathComponent, in: destDir)
        do {
            let dest = try FileMover.move(from: from, intoDirectory: destDir)
            log.markReverted(id: record.id)
            if let originalKey = finalLocations.first(where: {
                $0.value.path == from.path
            })?.key {
                finalLocations.removeValue(forKey: originalKey)
            }
            refreshRecent()
            NSLog("Magpie: reverted → \(dest.path)")
        } catch {
            NSLog("Magpie: revert failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func processBacklog() -> Int {
        BacklogProcessor.process(in: store.folders, using: watcher)
    }

    /// Number of files currently sitting in any watched folder's Recents/.
    func recentsCount() -> Int {
        var n = 0
        let fm = FileManager.default
        for parent in store.folders {
            let recents = ManagedFolder.recents.url(in: parent)
            guard let contents = try? fm.contentsOfDirectory(atPath: recents.path) else { continue }
            for name in contents where !FolderWatcher.shouldIgnore(name) {
                let url = recents.appendingPathComponent(name)
                let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                if isRegular { n += 1 }
            }
        }
        return n
    }

    /// Re-feed every file in Recents/ through the categorizer + filing pipeline.
    /// Used when files got orphaned (e.g. dropped by the old 20-cap bug, or stranded
    /// after a restart while waiting for categorization).
    @discardableResult
    func rescueRecents() -> Int {
        let fm = FileManager.default
        var injected: [URL] = []
        for parent in store.folders {
            let recents = ManagedFolder.recents.url(in: parent)
            guard let contents = try? fm.contentsOfDirectory(atPath: recents.path) else { continue }
            for name in contents where !FolderWatcher.shouldIgnore(name) {
                let recentsURL = recents.appendingPathComponent(name)
                let isRegular = (try? recentsURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                guard isRegular else { continue }
                let fakeOriginal = parent.appendingPathComponent(name)
                // Pre-populate so handleDetections won't re-stage (file is already in Recents).
                staged[fakeOriginal] = recentsURL
                injected.append(fakeOriginal)
            }
        }
        guard !injected.isEmpty else { return 0 }
        watcher.recordDetections(injected)
        return injected.count
    }

    private func watchedParent(of url: URL) -> URL? {
        let parent = url.deletingLastPathComponent()
        return store.folders.first { $0.path == parent.path }
    }

    private func refreshRecent() {
        recentMoves = log.recent(limit: 30)
    }
}
