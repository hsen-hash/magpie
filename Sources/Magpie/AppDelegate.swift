import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var costTimer: Timer?
    private var digestTimer: Timer?
    private var apiUsageObserver: NSObjectProtocol?
    private static let digestNotificationID = "magpie.dailyDigest"
    private let watchedFolders = WatchedFoldersStore()
    private let rulesStore = RulesStore()
    private lazy var fileWatcher = FileWatcherManager(store: watchedFolders)
    private lazy var coordinator = CategorizationCoordinator(
        watcher: fileWatcher,
        store: watchedFolders,
        rulesStore: rulesStore
    )
    private lazy var mover = MoveCoordinator(
        store: watchedFolders,
        watcher: fileWatcher,
        categorizer: coordinator
    )
    private lazy var digestService = DigestService(
        store: watchedFolders,
        moveLog: mover.log,
        coordinator: coordinator
    )
    private lazy var dashboard = DashboardController(
        store: watchedFolders,
        watcher: fileWatcher,
        coordinator: coordinator,
        mover: mover,
        rulesStore: rulesStore,
        digest: digestService
    )

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            self.setup()
        }
    }

    private func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: "Magpie")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 460)
        popover.behavior = .transient
        _ = fileWatcher
        _ = coordinator
        _ = mover
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                store: watchedFolders,
                watcher: fileWatcher,
                coordinator: coordinator,
                mover: mover,
                onOpenDashboard: { [weak self] in self?.dashboard.show() },
                onOpenDigest: { [weak self] in self?.dashboard.show(tab: .digest) }
            )
        )

        startCostTicker()
        startDigestScheduler()
    }

    // MARK: - Daily digest

    private func startDigestScheduler() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        digestService.onDigestReady = { [weak self] digest, background in
            Task { @MainActor in self?.handleDigestReady(digest, background: background) }
        }

        // Catch up shortly after launch if a day has already passed (or it's
        // the first run ever), then re-check hourly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.digestService.runDailyIfDue()
        }
        digestTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.digestService.runDailyIfDue() }
        }
    }

    private func handleDigestReady(_ digest: DailyDigest, background: Bool) {
        // Manual "Scan now" runs already show the result on screen — no need to
        // interrupt with a notification.
        guard background else { return }
        let content = UNMutableNotificationContent()
        content.title = "Magpie daily digest"
        if digest.hasActivity {
            var parts: [String] = []
            if digest.filesFiled > 0 { parts.append("\(digest.filesFiled) filed") }
            if digest.stuckInRecents > 0 { parts.append("\(digest.stuckInRecents) in Recents") }
            if digest.duplicateGroups > 0 { parts.append("\(digest.duplicateGroups) dup sets") }
            content.body = parts.joined(separator: " · ") + ". Tap for tips on staying tidy."
        } else {
            content.body = "Quiet day — your watched folders are tidy."
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.digestNotificationID,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // Show the digest tab when the notification is tapped.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.dashboard.show(tab: .digest)
            completionHandler()
        }
    }

    // Allow the banner to appear even while Magpie is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func startCostTicker() {
        refreshTooltip()
        // Update once a minute and on each new API call.
        costTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshTooltip() }
        }
        apiUsageObserver = NotificationCenter.default.addObserver(
            forName: .magpieApiUsageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshTooltip() }
        }
    }

    private func refreshTooltip() {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date()))
            ?? Date(timeIntervalSinceNow: -30 * 24 * 3600)
        let t = coordinator.apiLog.totals(since: startOfMonth)
        let pricing = PricingTable() // defaults; Settings editing comes later
        let cost = pricing.cost(for: t)
        let plural = t.calls == 1 ? "" : "s"
        let allLocal = t.calls > 0
            && t.localPromptTokens == t.promptTokens
            && t.localCandidateTokens == t.candidateTokens
        let costStr: String
        if allLocal {
            costStr = "$0 local"
        } else if cost < 0.0001 {
            costStr = "$0"
        } else {
            costStr = String(format: "$%.4f", cost)
        }
        statusItem?.button?.toolTip = "Magpie · \(costStr) this month · \(t.calls) call\(plural)"
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
