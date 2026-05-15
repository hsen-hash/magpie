import AppKit
import SwiftUI

@MainActor
final class DashboardController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    let store: WatchedFoldersStore
    let watcher: FileWatcherManager
    let coordinator: CategorizationCoordinator
    let mover: MoveCoordinator
    let rulesStore: RulesStore

    init(store: WatchedFoldersStore,
         watcher: FileWatcherManager,
         coordinator: CategorizationCoordinator,
         mover: MoveCoordinator,
         rulesStore: RulesStore) {
        self.store = store
        self.watcher = watcher
        self.coordinator = coordinator
        self.mover = mover
        self.rulesStore = rulesStore
    }

    func show() {
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
            rulesStore: rulesStore
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

    var body: some View {
        TabView {
            ActivityView(moveLog: moveLog, mover: mover, rulesStore: rulesStore)
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }

            RulesView(store: rulesStore)
                .tabItem { Label("Rules", systemImage: "wand.and.stars") }

            DuplicatesView(folders: watchedFolders.folders)
                .tabItem { Label("Duplicates", systemImage: "doc.on.doc") }

            APIUsageView(apiLog: apiLog)
                .tabItem { Label("API Usage", systemImage: "bolt.fill") }
        }
        .padding(12)
        .frame(minWidth: 760, minHeight: 500)
    }
}
