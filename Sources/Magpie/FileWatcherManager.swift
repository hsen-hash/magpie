import Foundation
import Combine

final class FileWatcherManager: ObservableObject {
    struct Detection: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let detectedAt: Date
    }

    @Published private(set) var recentDetections: [Detection] = []

    /// Emits each batch verbatim (uncapped). Use this for processing —
    /// `recentDetections` is capped for UI display only.
    let newDetectionsPublisher = PassthroughSubject<[Detection], Never>()

    private var watchers: [URL: FolderWatcher] = [:]
    private var cancellable: AnyCancellable?
    private let maxDisplay = 20

    init(store: WatchedFoldersStore) {
        cancellable = store.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] folders in self?.sync(to: folders) }
    }

    private func sync(to folders: [URL]) {
        let desired = Set(folders)

        for url in watchers.keys where !desired.contains(url) {
            watchers[url]?.stop()
            watchers.removeValue(forKey: url)
        }

        for url in desired where watchers[url] == nil {
            let watcher = FolderWatcher(url: url) { [weak self] newFiles in
                self?.record(newFiles)
            }
            watcher.start()
            watchers[url] = watcher
        }
    }

    private func record(_ urls: [URL]) {
        let now = Date()
        for u in urls { NSLog("Magpie: detected → \(u.path)") }
        let new = urls.map { Detection(url: $0, detectedAt: now) }
        // UI sees only the latest 20.
        recentDetections = Array((new + recentDetections).prefix(maxDisplay))
        // Processing sees the whole batch — no cap.
        newDetectionsPublisher.send(new)
    }

    /// Inject synthesized detections (used by BacklogProcessor).
    func recordDetections(_ urls: [URL]) {
        record(urls)
    }

    /// Tell the watcher for `parent` to ignore the next appearance of `name`.
    func suppressDetection(of name: String, in parent: URL) {
        watchers[parent]?.suppressDetection(of: name)
    }
}
