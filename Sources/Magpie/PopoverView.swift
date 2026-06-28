import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var store: WatchedFoldersStore
    @ObservedObject var watcher: FileWatcherManager
    @ObservedObject var coordinator: CategorizationCoordinator
    @ObservedObject var mover: MoveCoordinator
    let onOpenDashboard: () -> Void
    let onOpenDigest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            statusBanner
            watchedFoldersSection

            HStack(spacing: 8) {
                addFolderButton
                processBacklogButton
                rescueRecentsButton
            }
            .onAppear { refreshRecentsCount() }
            .onReceive(mover.$recentMoves) { _ in refreshRecentsCount() }

            if !inProgressDetections.isEmpty {
                Divider()
                inProgressSection
            }

            if !mover.recentMoves.isEmpty {
                Divider()
                recentMovesSection
            }

            Spacer()

            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            Image(systemName: "bird.fill").font(.title2)
            Text("Magpie").font(.headline)
            Spacer()
            Button { onOpenDigest() } label: {
                Image(systemName: "calendar.badge.clock")
            }
            .buttonStyle(.borderless)
            .help("Daily digest — what got added & how to avoid clutter")

            Button { onOpenDashboard() } label: {
                Image(systemName: "chart.bar.doc.horizontal")
            }
            .buttonStyle(.borderless)
            .help("Open Dashboard")

            Button { coordinator.openConfigInEditor() } label: {
                Image(systemName: "key")
            }
            .buttonStyle(.borderless)
            .help("Edit API key (~/.config/magpie/config.json)")

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Magpie")
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch coordinator.status {
        case .notConfigured(let provider):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(notConfiguredCopy(for: provider)).font(.caption)
                Spacer()
                Button(provider == .ollama ? "Setup…" : "Set Key…") {
                    coordinator.openConfigInEditor()
                }
                .controlSize(.small)
            }
            .padding(8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        case .error(let msg):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text(msg).font(.caption).lineLimit(3)
            }
            .padding(8)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        case .working:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Categorizing…").font(.caption).foregroundStyle(.secondary)
            }
        case .idle:
            EmptyView()
        }
    }

    private var watchedFoldersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Watched folders")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if store.folders.isEmpty {
                Text("No folders yet — add one below.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(store.folders, id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent).font(.callout).lineLimit(1)
                            Text(url.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button { store.remove(url) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop watching")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var addFolderButton: some View {
        Button { showOpenPanel() } label: {
            Label("Add Folder…", systemImage: "plus")
        }
        .controlSize(.regular)
    }

    private var processBacklogButton: some View {
        Button {
            confirmAndProcessBacklog()
        } label: {
            Label("Process Backlog", systemImage: "tray.and.arrow.down")
        }
        .controlSize(.regular)
        .disabled(store.folders.isEmpty || isNotConfigured)
    }

    private var isNotConfigured: Bool {
        if case .notConfigured = coordinator.status { return true }
        return false
    }

    private func notConfiguredCopy(for provider: CategorizerProvider) -> String {
        switch provider {
        case .gemini: return "Gemini API key not set."
        case .ollama: return "Ollama model not configured."
        }
    }

    @State private var recentsCount: Int = 0
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    private var rescueRecentsButton: some View {
        let stuck = recentsCount
        return Group {
            if stuck > 0 {
                Button {
                    let n = mover.rescueRecents()
                    NSLog("Magpie: rescue triggered for \(n) files")
                } label: {
                    Label("Rescue \(stuck) in Recents", systemImage: "arrow.up.bin")
                }
                .controlSize(.regular)
                .tint(.orange)
                .disabled(isNotConfigured)
                .help("Re-process files stranded in Recents/")
            }
        }
    }

    private var inProgressDetections: [FileWatcherManager.Detection] {
        watcher.recentDetections.filter { mover.finalLocations[$0.url] == nil }
    }

    private var inProgressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In progress")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(inProgressDetections) { d in
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(d.url.lastPathComponent).font(.caption).lineLimit(1)
                            Spacer()
                            if let decision = coordinator.categories[d.url] {
                                Text(decision.category)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                                    .help(decision.reason)
                            } else {
                                Text(d.detectedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 100)
        }
    }

    private var recentMovesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent moves")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(mover.recentMoves) { record in
                        moveRow(record)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func moveRow(_ record: MoveRecord) -> some View {
        let filename = (record.newPath as NSString).lastPathComponent
        let categoryFolder = (record.newPath as NSString)
            .deletingLastPathComponent
            .components(separatedBy: "/")
            .last ?? ""

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: record.reverted ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                    .foregroundStyle(record.reverted ? Color.secondary : .green)
                Text(filename)
                    .font(.caption)
                    .lineLimit(1)
                    .strikethrough(record.reverted)
                Spacer()
                Text(categoryFolder)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                if !record.reverted {
                    Button { openFile(record) } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderless)
                    .help("Open file")

                    Button { revealFile(record) } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")

                    Button { mover.revert(record) } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Revert to original location")
                }
            }
            Text(prettyPath(URL(fileURLWithPath: record.newPath)))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 22)
        }
        .opacity(record.reverted ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !record.reverted { openFile(record) }
        }
    }

    /// Open the filed document in its default application. Falls back to
    /// revealing it in Finder if the file has since moved or been deleted.
    private func openFile(_ record: MoveRecord) {
        let url = URL(fileURLWithPath: record.newPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func revealFile(_ record: MoveRecord) {
        let url = URL(fileURLWithPath: record.newPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func prettyPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var p = url.path
        if p.hasPrefix(home) {
            p = "~" + p.dropFirst(home.count)
        }
        return "→ " + p
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        panel.message = "Choose a folder for Magpie to watch."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            store.add(url)
        }
    }

    private func refreshRecentsCount() {
        recentsCount = mover.recentsCount()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: launchAtLogin) { newVal in
                        launchError = LaunchAtLogin.setEnabled(newVal)
                        // Re-sync in case the system overrode (e.g., requires approval)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                    .font(.caption)
                Spacer()
                Text("Magpie v0.3")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let launchError {
                Text(launchError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    private func confirmAndProcessBacklog() {
        let backlog = BacklogProcessor.discover(in: store.folders)
        let n = backlog.count
        if n == 0 {
            let info = NSAlert()
            info.messageText = "No backlog"
            info.informativeText = "No pre-existing top-level files to process."
            info.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Process \(n) existing file\(n == 1 ? "" : "s")?"
        alert.informativeText = "Magpie will move every top-level file in your watched folders into Recents, ask \(coordinator.activeProvider.displayName) to categorize them, then file them into AI Library. You can revert any move from this menu."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Process \(n) file\(n == 1 ? "" : "s")")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            _ = mover.processBacklog()
        }
    }
}
