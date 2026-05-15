import Foundation
import AppKit

final class WatchedFoldersStore: ObservableObject {
    @Published private(set) var folders: [URL] = []

    private let defaultsKey = "watchedFolderBookmarks_v1"

    init() {
        load()
        if folders.isEmpty {
            if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                add(downloads)
            }
        }
    }

    func add(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !folders.contains(where: { $0.path == standardized.path }) else { return }

        do {
            let data = try standardized.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var stored = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] ?? []
            stored.append(data)
            UserDefaults.standard.set(stored, forKey: defaultsKey)
            _ = standardized.startAccessingSecurityScopedResource()
            Bootstrap.ensureManagedSubfolders(at: standardized)
            folders.append(standardized)
        } catch {
            NSLog("Magpie: bookmark failed for \(standardized.path): \(error)")
        }
    }

    func remove(_ url: URL) {
        guard let idx = folders.firstIndex(of: url) else { return }
        folders[idx].stopAccessingSecurityScopedResource()
        folders.remove(at: idx)
        var stored = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] ?? []
        if idx < stored.count {
            stored.remove(at: idx)
            UserDefaults.standard.set(stored, forKey: defaultsKey)
        }
    }

    private func load() {
        let stored = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] ?? []
        var resolvedURLs: [URL] = []
        var refreshedData: [Data] = []

        for data in stored {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            _ = url.startAccessingSecurityScopedResource()
            resolvedURLs.append(url)

            if isStale, let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                refreshedData.append(fresh)
            } else {
                refreshedData.append(data)
            }
        }

        UserDefaults.standard.set(refreshedData, forKey: defaultsKey)
        for url in resolvedURLs {
            Bootstrap.ensureManagedSubfolders(at: url)
        }
        folders = resolvedURLs
    }
}
