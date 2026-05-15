import SwiftUI
import AppKit

struct DuplicatesView: View {
    let folders: [URL]

    @State private var groups: [DuplicateGroup] = []
    @State private var scanning = false
    @State private var progress = ScanProgress()
    @State private var scanner = DedupScanner()
    @State private var lastScanAt: Date?
    @State private var lastFilesConsidered: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Duplicate files")
                    .font(.title2)
                    .bold()
                Spacer()
                if scanning {
                    ProgressView(value: Double(progress.current),
                                 total: Double(max(progress.total, 1)))
                        .frame(width: 160)
                    Text("\(progress.phase) \(progress.current)/\(progress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Cancel") { Task { await scanner.cancel() } }
                } else {
                    Button {
                        runScan()
                    } label: {
                        Label("Scan now", systemImage: "doc.on.doc")
                    }
                    .disabled(folders.isEmpty)
                }
            }

            if groups.isEmpty && !scanning {
                VStack(spacing: 10) {
                    Image(systemName: lastScanAt == nil ? "doc.on.doc" : "checkmark.seal")
                        .font(.system(size: 48))
                        .foregroundStyle(lastScanAt == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.green))
                    Text(lastScanAt == nil ? "No scan yet" : "No duplicates found")
                        .font(.headline)
                    Text(lastScanAt == nil
                         ? "Click \"Scan now\" to hash every file (4 KB – 500 MB) in your watched folders and flag identical content. Common dev folders (node_modules, .git, build) are skipped."
                         : "Scanned \(lastFilesConsidered.formatted()) files at \(lastScanAt!.formatted(date: .omitted, time: .shortened)). No identical-content groups detected.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                summary
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(groups) { group in
                            groupCard(group)
                        }
                    }
                }
            }
        }
        .padding(8)
    }

    private var summary: some View {
        let totalDupes = groups.reduce(0) { $0 + $1.files.count - 1 }
        let wasted = groups.reduce(Int64(0)) { $0 + Int64($1.files.count - 1) * $1.size }
        return HStack(spacing: 24) {
            VStack(alignment: .leading) {
                Text("\(groups.count)").font(.title2).bold()
                Text("duplicate groups").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading) {
                Text("\(totalDupes)").font(.title2).bold()
                Text("redundant files").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading) {
                Text(ByteCountFormatter.string(fromByteCount: wasted, countStyle: .file))
                    .font(.title2).bold()
                Text("reclaimable").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.on.doc.fill").foregroundStyle(.orange)
                Text("\(group.files.count) copies · " +
                     ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file) +
                     " each")
                    .font(.headline)
                Spacer()
                Text(String(group.hash.prefix(10)))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(group.files.enumerated()), id: \.offset) { (idx, url) in
                HStack(spacing: 8) {
                    Image(systemName: idx == 0 ? "checkmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(idx == 0 ? Color.green : .secondary)
                    Text(idx == 0 ? "Keep" : "Duplicate")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            (idx == 0 ? Color.green : Color.orange).opacity(0.18),
                            in: Capsule()
                        )
                    Text(prettify(url.path))
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url.path)
                    Spacer()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                    if idx > 0 {
                        Button {
                            moveToTrash(url, in: group)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Move to Trash")
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func runScan() {
        scanning = true
        progress = ScanProgress()
        let folders = self.folders
        Task {
            let result = await scanner.scan(parents: folders) { p in
                Task { @MainActor in self.progress = p }
            }
            await MainActor.run {
                self.groups = result.groups
                self.scanning = false
                self.lastScanAt = Date()
                self.lastFilesConsidered = result.filesEnumerated
            }
        }
    }

    private func moveToTrash(_ url: URL, in group: DuplicateGroup) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            if let idx = groups.firstIndex(of: group) {
                var updated = groups[idx]
                updated.files.removeAll { $0 == url }
                if updated.files.count <= 1 {
                    groups.remove(at: idx)
                } else {
                    groups[idx] = updated
                }
            }
        } catch {
            NSLog("Magpie: trash failed: \(error.localizedDescription)")
        }
    }

    private func prettify(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
