import Foundation

/// One-shot migration from the previous "Spark" identity:
///   ~/.config/spark/  → ~/.config/magpie/
///   ~/Library/Preferences/com.hamzas.spark.plist  → UserDefaults.standard (com.hamzas.magpie)
///
/// Safe to call on every launch — each step is idempotent and exits early if the
/// new target already exists.
enum Migration {
    static func runIfNeeded() {
        migrateConfigDirectory()
        migrateUserDefaults()
    }

    private static func migrateConfigDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let oldDir = home.appendingPathComponent(".config/spark")
        let newDir = home.appendingPathComponent(".config/magpie")
        let fm = FileManager.default
        guard fm.fileExists(atPath: oldDir.path),
              !fm.fileExists(atPath: newDir.path) else { return }
        do {
            try fm.createDirectory(at: newDir.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try fm.moveItem(at: oldDir, to: newDir)
            NSLog("Magpie: migrated ~/.config/spark → ~/.config/magpie")
        } catch {
            NSLog("Magpie: config migration failed: \(error.localizedDescription)")
        }
    }

    private static func migrateUserDefaults() {
        let bookmarksKey = "watchedFolderBookmarks_v1"
        guard UserDefaults.standard.array(forKey: bookmarksKey) == nil else { return }

        let library = FileManager.default.urls(for: .libraryDirectory,
                                               in: .userDomainMask).first!
        let oldPlist = library.appendingPathComponent("Preferences/com.hamzas.spark.plist")
        guard FileManager.default.fileExists(atPath: oldPlist.path),
              let data = try? Data(contentsOf: oldPlist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }

        if let bookmarks = dict[bookmarksKey] {
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
            NSLog("Magpie: migrated watched-folder bookmarks from Spark prefs")
        }
    }
}
