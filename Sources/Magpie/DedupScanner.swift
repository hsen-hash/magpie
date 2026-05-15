import Foundation
import CryptoKit

struct DuplicateGroup: Identifiable, Hashable {
    let id = UUID()
    let hash: String
    let size: Int64
    var files: [URL]
}

struct ScanProgress {
    var current: Int = 0
    var total: Int = 0
    var phase: String = ""
}

struct ScanResult {
    let groups: [DuplicateGroup]
    let filesEnumerated: Int
    let filesHashed: Int
}

actor DedupScanner {
    private let maxBytes: Int64 = 500 * 1024 * 1024 // skip > 500 MB
    private let minBytes: Int64 = 4 * 1024          // skip < 4 KB (configs, lockfiles, etc.)
    private static let excludedDirs: Set<String> = [
        "node_modules", ".git", ".cache", "__pycache__", ".next",
        "dist", "build", "target", ".venv", "venv", "Pods",
        ".gradle", ".idea", "DerivedData", ".terraform",
        ".pytest_cache", ".mypy_cache", ".parcel-cache",
    ]
    private var isCancelled = false

    func cancel() { isCancelled = true }

    private func emptyResult() -> ScanResult {
        ScanResult(groups: [], filesEnumerated: 0, filesHashed: 0)
    }

    func scan(parents: [URL], progress: @escaping @Sendable (ScanProgress) -> Void) async -> ScanResult {
        isCancelled = false

        let fm = FileManager.default
        var allFiles: [(URL, Int64)] = []
        var prog = ScanProgress(phase: "Enumerating")
        progress(prog)

        for parent in parents {
            if isCancelled { return emptyResult() }
            let enumerator = fm.enumerator(
                at: parent,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let item = enumerator?.nextObject() as? URL {
                if isCancelled { return emptyResult() }
                let vals = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey])

                // Prune excluded directories so we don't even enumerate their children.
                if vals?.isDirectory == true,
                   Self.excludedDirs.contains(item.lastPathComponent) {
                    enumerator?.skipDescendants()
                    continue
                }

                guard vals?.isRegularFile == true else { continue }
                let size = Int64(vals?.fileSize ?? 0)
                if size < minBytes || size > maxBytes { continue }
                allFiles.append((item, size))

                if allFiles.count % 200 == 0 {
                    progress(ScanProgress(current: allFiles.count, total: 0, phase: "Enumerating"))
                }
            }
        }

        // Group by size first — only hash within size groups, since different sizes can't match.
        let sizeGroups = Dictionary(grouping: allFiles, by: { $0.1 })
            .filter { $0.value.count > 1 }
            .mapValues { $0.map(\.0) }

        let totalCandidates = sizeGroups.values.reduce(0) { $0 + $1.count }
        prog = ScanProgress(current: 0, total: totalCandidates, phase: "Hashing")
        progress(prog)

        var hashed: [String: (Int64, [URL])] = [:] // hash → (size, files)
        var done = 0
        for (size, files) in sizeGroups {
            for file in files {
                if isCancelled { return emptyResult() }
                if let h = sha256(of: file) {
                    var entry = hashed[h] ?? (size, [])
                    entry.1.append(file)
                    hashed[h] = entry
                }
                done += 1
                if done % 5 == 0 || done == totalCandidates {
                    progress(ScanProgress(current: done, total: totalCandidates, phase: "Hashing"))
                }
            }
        }

        let groups = hashed
            .filter { $0.value.1.count > 1 }
            .map { DuplicateGroup(hash: $0.key, size: $0.value.0, files: $0.value.1) }
            .sorted { $0.size > $1.size }

        progress(ScanProgress(current: totalCandidates, total: totalCandidates, phase: "Done"))
        return ScanResult(
            groups: groups,
            filesEnumerated: allFiles.count,
            filesHashed: totalCandidates
        )
    }

    private func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1 << 20 // 1 MB
        while true {
            let data = (try? handle.read(upToCount: chunkSize)) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
