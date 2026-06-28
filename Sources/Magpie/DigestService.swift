import Foundation
import Combine
import AppKit

/// Builds the daily folder digest: what Magpie filed, what's piling up, and
/// concrete advice on avoiding clutter. Runs on a daily schedule (driven by
/// `AppDelegate`) or on demand from the UI.
@MainActor
final class DigestService: ObservableObject {
    @Published private(set) var latest: DailyDigest?
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private let store: WatchedFoldersStore
    private let moveLog: MoveLog
    private let coordinator: CategorizationCoordinator
    private let persistence = DigestStore()

    /// Called when a fresh digest is ready. `background` is true for the
    /// scheduled run (AppDelegate uses it to decide whether to post a
    /// notification) and false for manual "Scan now".
    var onDigestReady: ((DailyDigest, _ background: Bool) -> Void)?

    init(store: WatchedFoldersStore,
         moveLog: MoveLog,
         coordinator: CategorizationCoordinator) {
        self.store = store
        self.moveLog = moveLog
        self.coordinator = coordinator
        self.latest = persistence.load()
    }

    var lastRun: Date? { persistence.lastRun }

    /// True once a full day has elapsed since the last run (or it's never run).
    func isDue(now: Date = Date()) -> Bool {
        guard let last = persistence.lastRun else { return true }
        return now.timeIntervalSince(last) >= 24 * 3600
    }

    /// Run the scheduled digest if it's due. Safe to call often.
    func runDailyIfDue() {
        guard isDue(), !isRunning else { return }
        Task { await generate(background: true) }
    }

    /// Build a fresh digest now and persist it.
    func generate(background: Bool) async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        defer { isRunning = false }

        let now = Date()
        // Window covers everything since the last run, defaulting to 24h on the
        // first ever run so the inaugural digest isn't empty-by-construction.
        let periodStart = persistence.lastRun
            ?? Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)

        var digest = await buildStats(periodStart: periodStart, now: now)
        await attachNarrative(to: &digest)

        latest = digest
        persistence.save(digest: digest, lastRun: now)
        onDigestReady?(digest, background)
    }

    // MARK: - Stats

    private func buildStats(periodStart: Date, now: Date) async -> DailyDigest {
        let folders = store.folders
        let fm = FileManager.default

        // 1. What Magpie filed in the window (from the move journal).
        let moves = moveLog.recent(limit: 5000)
            .filter { !$0.reverted && $0.timestamp >= periodStart }

        var byCat: [String: Int] = [:]
        var bytesFiled: Int64 = 0
        var newFiles: [DigestFileRef] = []
        for m in moves {
            let cat = Self.categoryName(of: m.newPath)
            byCat[cat, default: 0] += 1
            let attrs = try? fm.attributesOfItem(atPath: m.newPath)
            if let size = (attrs?[.size] as? NSNumber)?.int64Value {
                bytesFiled += size
                newFiles.append(DigestFileRef(path: m.newPath, bytes: size))
            }
        }
        let byCategory = byCat
            .map { DigestCategoryCount(category: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.category < $1.category }
        let largestNew = Array(newFiles.sorted { $0.bytes > $1.bytes }.prefix(5))

        // 2. Files sitting uncategorized in Recents across all watched folders.
        var stuck = 0
        for parent in folders {
            let recents = ManagedFolder.recents.url(in: parent)
            guard let contents = try? fm.contentsOfDirectory(atPath: recents.path) else { continue }
            for name in contents where !FolderWatcher.shouldIgnore(name) {
                let url = recents.appendingPathComponent(name)
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    stuck += 1
                }
            }
        }

        // 3. Duplicates + reclaimable space (reuse the dedup engine).
        let scan = await DedupScanner().scan(parents: folders, progress: { _ in })
        let reclaimable = scan.groups.reduce(Int64(0)) { acc, g in
            acc + g.size * Int64(max(0, g.files.count - 1))
        }

        let tips = Self.buildTips(
            filesFiled: moves.count,
            byCategory: byCategory,
            largestNew: largestNew,
            stuckInRecents: stuck,
            duplicateGroups: scan.groups.count,
            reclaimableBytes: reclaimable,
            folderCount: folders.count
        )

        return DailyDigest(
            generatedAt: now,
            periodStart: periodStart,
            filesFiled: moves.count,
            bytesFiled: bytesFiled,
            byCategory: byCategory,
            largestNew: largestNew,
            stuckInRecents: stuck,
            duplicateGroups: scan.groups.count,
            reclaimableBytes: reclaimable,
            tips: tips,
            narrative: nil,
            narrativeModel: nil
        )
    }

    /// Local, deterministic clutter advice derived straight from the numbers.
    /// Always present — the AI narrative only adds colour on top of these.
    private static func buildTips(
        filesFiled: Int,
        byCategory: [DigestCategoryCount],
        largestNew: [DigestFileRef],
        stuckInRecents: Int,
        duplicateGroups: Int,
        reclaimableBytes: Int64,
        folderCount: Int
    ) -> [String] {
        var tips: [String] = []

        if folderCount == 0 {
            tips.append("No folders are being watched yet — add one from the Magpie menu to start organizing.")
            return tips
        }

        if stuckInRecents > 0 {
            tips.append("\(stuckInRecents) file\(stuckInRecents == 1 ? " is" : "s are") stranded in Recents/. Open Magpie and hit “Rescue” to re-file them.")
        }

        if duplicateGroups > 0 {
            tips.append("\(duplicateGroups) duplicate set\(duplicateGroups == 1 ? "" : "s") found (~\(reclaimableBytes.humanBytes) reclaimable). Clear them from the Duplicates tab.")
        }

        // A category dominating the intake is a strong candidate for a rule.
        if filesFiled >= 5, let top = byCategory.first,
           Double(top.count) / Double(filesFiled) >= 0.5 {
            tips.append("Over half of new files landed in “\(top.category)”. Add a rule so they skip the AI and file instantly.")
        }

        if let biggest = largestNew.first, biggest.bytes >= 100 * 1024 * 1024 {
            tips.append("Largest new arrival was \(biggest.name) (\(biggest.bytes.humanBytes)). Installers and archives are usually safe to delete once used.")
        }

        if filesFiled == 0 && stuckInRecents == 0 && duplicateGroups == 0 {
            tips.append("Quiet period — nothing new piled up. Your watched folders are tidy.")
        } else if tips.isEmpty {
            tips.append("Things look under control. Keep an eye on Recents/ so files don’t sit uncategorized.")
        }

        return tips
    }

    // MARK: - AI narrative

    private func attachNarrative(to digest: inout DailyDigest) async {
        guard let completer = coordinator.textCompleter else { return }

        let prompt = Self.narrativePrompt(for: digest)
        do {
            let result = try await completer.complete(prompt: prompt)
            coordinator.apiLog.record(
                provider: coordinator.activeProvider.rawValue,
                model: result.model,
                filenameCount: 0,
                promptTokens: result.usage.promptTokens,
                candidateTokens: result.usage.candidateTokens,
                totalTokens: result.usage.totalTokens,
                httpStatus: result.usage.httpStatus
            )
            NotificationCenter.default.post(name: .magpieApiUsageDidChange, object: nil)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                digest.narrative = text
                digest.narrativeModel = result.model
            }
        } catch {
            // Non-fatal: the digest still has its heuristic tips.
            lastError = error.localizedDescription
            NSLog("Magpie: digest narrative failed: \(error.localizedDescription)")
        }
    }

    private static func narrativePrompt(for d: DailyDigest) -> String {
        let cats = d.byCategory.prefix(8)
            .map { "\($0.category): \($0.count)" }
            .joined(separator: ", ")
        let largest = d.largestNew.prefix(3)
            .map { "\($0.name) (\($0.bytes.humanBytes))" }
            .joined(separator: ", ")

        let stats = """
        - Files filed since last digest: \(d.filesFiled) (\(d.bytesFiled.humanBytes) total)
        - By category: \(cats.isEmpty ? "none" : cats)
        - Largest new files: \(largest.isEmpty ? "none" : largest)
        - Files stuck uncategorized in Recents: \(d.stuckInRecents)
        - Duplicate sets: \(d.duplicateGroups) (~\(d.reclaimableBytes.humanBytes) reclaimable)
        """

        return """
        You are the assistant inside Magpie, a macOS file organizer. Write the user's daily folder digest.

        Today's data:
        \(stats)

        Write two short paragraphs in a friendly, concrete tone:
        1. A one-to-two sentence recap of what was added and where it went.
        2. Specific, actionable advice to avoid clutter, grounded ONLY in the data above (e.g. clearing Recents, removing duplicates, deleting large installers, adding a rule for a dominant category). If everything is tidy, say so briefly.

        Keep it under 120 words. Plain text only — no markdown, no headings, no bullet symbols.
        """
    }

    // MARK: - Helpers

    /// Pull the category folder out of a `.../AI Library/<Category>/<file>` path.
    static func categoryName(of path: String) -> String {
        let parts = path.components(separatedBy: "/")
        if let idx = parts.lastIndex(of: ManagedFolder.aiLibrary.rawValue),
           idx + 1 < parts.count - 1 {
            return parts[idx + 1]
        }
        // Fall back to the immediate parent folder name.
        return (path as NSString).deletingLastPathComponent
            .components(separatedBy: "/").last ?? "Uncategorized"
    }
}
