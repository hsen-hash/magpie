import Foundation

enum FileMover {
    enum MoveError: LocalizedError {
        case sourceNotFound(URL)
        case createDirFailed(URL, Error)
        case moveFailed(URL, URL, Error)

        var errorDescription: String? {
            switch self {
            case .sourceNotFound(let url):
                return "Source not found: \(url.path)"
            case .createDirFailed(let url, let err):
                return "Couldn't create dir \(url.path): \(err.localizedDescription)"
            case .moveFailed(let from, let to, let err):
                return "Move failed \(from.path) → \(to.path): \(err.localizedDescription)"
            }
        }
    }

    /// Move `source` into `destDir`. Creates `destDir` if missing. Returns the final URL,
    /// appending " (2)", " (3)"… to avoid collisions.
    @discardableResult
    static func move(from source: URL, intoDirectory destDir: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw MoveError.sourceNotFound(source)
        }
        if !fm.fileExists(atPath: destDir.path) {
            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            } catch {
                throw MoveError.createDirFailed(destDir, error)
            }
        }
        let dest = uniqueDestination(in: destDir, name: source.lastPathComponent)
        do {
            try fm.moveItem(at: source, to: dest)
            return dest
        } catch {
            throw MoveError.moveFailed(source, dest, error)
        }
    }

    private static func uniqueDestination(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        let first = dir.appendingPathComponent(name)
        if !fm.fileExists(atPath: first.path) { return first }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 2
        while true {
            let newName = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            let url = dir.appendingPathComponent(newName)
            if !fm.fileExists(atPath: url.path) { return url }
            i += 1
            if i > 9999 { return url } // give up — pathological case
        }
    }

    static func sanitizeFolderName(_ raw: String) -> String {
        let bad: Set<Character> = ["/", ":", "\\", "*", "?", "\"", "<", ">", "|"]
        let cleaned = raw.filter { !bad.contains($0) }.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Uncategorized" : cleaned
    }
}
