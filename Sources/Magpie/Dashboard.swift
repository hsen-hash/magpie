import AppKit
import SwiftUI

enum DashboardTab: Hashable {
    case activity, digest, rules, duplicates, api
}

/// Lets external triggers (notification click, popover button) select which
/// dashboard tab is shown when the window opens.
@MainActor
final class DashboardRouter: ObservableObject {
    @Published var selectedTab: DashboardTab = .activity
}

@MainActor
final class DashboardController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let router = DashboardRouter()

    let store: WatchedFoldersStore
    let watcher: FileWatcherManager
    let coordinator: CategorizationCoordinator
    let mover: MoveCoordinator
    let rulesStore: RulesStore
    let digest: DigestService

    init(store: WatchedFoldersStore,
         watcher: FileWatcherManager,
         coordinator: CategorizationCoordinator,
         mover: MoveCoordinator,
         rulesStore: RulesStore,
         digest: DigestService) {
        self.store = store
        self.watcher = watcher
        self.coordinator = coordinator
        self.mover = mover
        self.rulesStore = rulesStore
        self.digest = digest
    }

    func show(tab: DashboardTab? = nil) {
        if let tab { router.selectedTab = tab }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = DashboardView(
            apiLog: coordinator.apiLog,
            moveLog: mover.log,
            mover: mover,
            watchedFolders: store,
            rulesStore: rulesStore,
            digest: digest,
            router: router
        )
        let host = NSHostingController(rootView: view)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Magpie Dashboard"
        win.contentViewController = host
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        // Keep the window alive so reopening is fast.
    }
}

struct DashboardView: View {
    let apiLog: ApiUsageLog
    let moveLog: MoveLog
    @ObservedObject var mover: MoveCoordinator
    @ObservedObject var watchedFolders: WatchedFoldersStore
    @ObservedObject var rulesStore: RulesStore
    @ObservedObject var digest: DigestService
    @ObservedObject var router: DashboardRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ActivityView(moveLog: moveLog, mover: mover, rulesStore: rulesStore)
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
                .tag(DashboardTab.activity)

            DigestView(digest: digest)
                .tabItem { Label("Digest", systemImage: "calendar.badge.clock") }
                .tag(DashboardTab.digest)

            RulesView(store: rulesStore)
                .tabItem { Label("Rules", systemImage: "wand.and.stars") }
                .tag(DashboardTab.rules)

            DuplicatesView(folders: watchedFolders.folders)
                .tabItem { Label("Duplicates", systemImage: "doc.on.doc") }
                .tag(DashboardTab.duplicates)

            APIUsageView(apiLog: apiLog)
                .tabItem { Label("API Usage", systemImage: "bolt.fill") }
                .tag(DashboardTab.api)
        }
        .padding(12)
        .frame(minWidth: 760, minHeight: 500)
    }
}
