import Foundation

enum ManagedFolder: String, CaseIterable {
    case recents = "Recents"
    case aiLibrary = "AI Library"
    case manualLibrary = "Manual Library"

    static let allNames: Set<String> = Set(allCases.map { $0.rawValue })

    func url(in parent: URL) -> URL {
        parent.appendingPathComponent(rawValue, isDirectory: true)
    }
}

enum Bootstrap {
    /// Idempotently create the three managed subfolders inside a watched folder.
    /// Safe to call repeatedly — only creates what's missing.
    static func ensureManagedSubfolders(at parent: URL) {
        let fm = FileManager.default
        for folder in ManagedFolder.allCases {
            let sub = folder.url(in: parent)
            guard !fm.fileExists(atPath: sub.path) else { continue }
            do {
                try fm.createDirectory(at: sub, withIntermediateDirectories: false)
                NSLog("Magpie: created \(sub.path)")
            } catch {
                NSLog("Magpie: createDirectory failed for \(sub.path): \(error)")
            }
        }
    }
}
