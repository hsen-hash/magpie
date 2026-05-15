import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var costTimer: Timer?
    private var apiUsageObserver: NSObjectProtocol?
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
    private lazy var dashboard = DashboardController(
        store: watchedFolders,
        watcher: fileWatcher,
        coordinator: coordinator,
        mover: mover,
        rulesStore: rulesStore
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
                onOpenDashboard: { [weak self] in self?.dashboard.show() }
            )
        )

        startCostTicker()
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
        let cost = pricing.cost(prompt: t.promptTokens, output: t.candidateTokens)
        let plural = t.calls == 1 ? "" : "s"
        let costStr: String
        if cost < 0.0001 {
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
