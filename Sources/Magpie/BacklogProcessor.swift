import Foundation

enum BacklogProcessor {
    /// Returns the URLs of top-level files in `parents` that aren't already
    /// being tracked: regular files, not hidden, not in-progress downloads,
    /// not the three managed folders.
    static func discover(in parents: [URL]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for parent in parents {
            guard let names = try? fm.contentsOfDirectory(atPath: parent.path) else { continue }
            for name in names {
                if FolderWatcher.shouldIgnore(name) { continue }
                if ManagedFolder.allNames.contains(name) { continue }
                let url = parent.appendingPathComponent(name)
                let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                if isRegular { result.append(url) }
            }
        }
        return result
    }

    /// Feed pre-existing files into the watcher as if they had just been detected.
    /// Downstream (CategorizationCoordinator + MoveCoordinator) handles the rest.
    @MainActor
    static func process(in parents: [URL], using watcher: FileWatcherManager) -> Int {
        let urls = discover(in: parents)
        guard !urls.isEmpty else { return 0 }
        watcher.recordDetections(urls)
        return urls.count
    }
}
