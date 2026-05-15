import Foundation
import AppKit

@MainActor
final class RulesStore: ObservableObject {
    @Published private(set) var rules: [CategorizationRule] = []
    @Published private(set) var hitsThisSession: [UUID: Int] = [:]

    private let url: URL

    init() {
        self.url = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/magpie/rules.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: url) else {
            rules = []
            return
        }
        do {
            rules = try JSONDecoder().decode([CategorizationRule].self, from: data)
        } catch {
            NSLog("Magpie: rules.json decode failed: \(error.localizedDescription)")
            rules = []
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(rules)
            try data.write(to: url)
            // Make sure the file is owner-only readable like config.json
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            NSLog("Magpie: failed to save rules.json: \(error.localizedDescription)")
        }
    }

    func add(_ rule: CategorizationRule) {
        rules.append(rule)
        save()
    }

    func update(_ rule: CategorizationRule) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[idx] = rule
        save()
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        hitsThisSession.removeValue(forKey: id)
        save()
    }

    func move(id: UUID, direction: Int) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + direction
        guard target >= 0, target < rules.count else { return }
        rules.swapAt(idx, target)
        save()
    }

    /// First matching rule wins. Records a hit when matched.
    /// Returns the full matching rule, or nil if no rule applied.
    func matchRule(for filename: String) -> CategorizationRule? {
        for rule in rules where rule.enabled {
            if rule.matches(filename: filename) {
                hitsThisSession[rule.id, default: 0] += 1
                return rule
            }
        }
        return nil
    }

    func openInEditor() {
        if !FileManager.default.fileExists(atPath: url.path) {
            save() // create empty file
        }
        NSWorkspace.shared.open(url)
    }
}
