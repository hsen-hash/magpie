import Foundation

final class FolderWatcher {
    let url: URL

    private let queue: DispatchQueue
    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var knownNames: Set<String> = []
    private let debounce: TimeInterval = 2.0
    private let onNewFiles: ([URL]) -> Void

    init(url: URL, onNewFiles: @escaping ([URL]) -> Void) {
        self.url = url
        self.queue = DispatchQueue(label: "magpie.watcher.\(url.lastPathComponent)")
        self.onNewFiles = onNewFiles
    }

    func start() {
        knownNames = currentNames()

        let opened = open(url.path, O_EVTONLY)
        guard opened >= 0 else {
            NSLog("Magpie: open() failed for \(url.path), errno=\(errno)")
            return
        }
        fd = opened

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        src.setEventHandler { [weak self] in self?.scheduleScan() }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fd >= 0 { close(self.fd); self.fd = -1 }
        }
        src.resume()
        source = src
        NSLog("Magpie: watching \(url.path)")
    }

    /// Pretend a filename is already known so the next scan won't report it as new.
    /// Used to prevent re-detection loops when Magpie itself drops a file back into
    /// the watched folder (e.g., during a revert).
    func suppressDetection(of name: String) {
        queue.async { [weak self] in
            self?.knownNames.insert(name)
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    private func scheduleScan() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.scan() }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private func scan() {
        let current = currentNames()
        let added = current.subtracting(knownNames)
        knownNames = current

        let newURLs = added
            .filter { !Self.shouldIgnore($0) }
            .map { url.appendingPathComponent($0) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }

        guard !newURLs.isEmpty else { return }
        DispatchQueue.main.async { [onNewFiles] in onNewFiles(newURLs) }
    }

    private func currentNames() -> Set<String> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return [] }
        return Set(names)
    }

    static func shouldIgnore(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        let lower = name.lowercased()
        return lower.hasSuffix(".crdownload")
            || lower.hasSuffix(".part")
            || lower.hasSuffix(".download")
            || lower.hasSuffix(".tmp")
    }

    deinit { stop() }
}
