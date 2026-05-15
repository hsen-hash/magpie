import SwiftUI
import AppKit

struct ActivityView: View {
    let moveLog: MoveLog
    @ObservedObject var mover: MoveCoordinator
    @ObservedObject var rulesStore: RulesStore

    @State private var query: String = ""
    @State private var hideReverted = false
    @State private var allMoves: [MoveRecord] = []
    @State private var suggestionTarget: MoveRecord?

    private var filtered: [MoveRecord] {
        var rows = allMoves
        if hideReverted { rows = rows.filter { !$0.reverted } }
        if !query.isEmpty {
            let q = query.lowercased()
            rows = rows.filter {
                $0.originalPath.lowercased().contains(q) ||
                $0.newPath.lowercased().contains(q)
            }
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Move journal")
                    .font(.title2)
                    .bold()
                Spacer()
                Text("\(filtered.count) of \(allMoves.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Filter by filename or path", text: $query)
                    .textFieldStyle(.roundedBorder)
                Toggle("Hide reverted", isOn: $hideReverted)
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")
            }

            Table(filtered) {
                TableColumn("File") { rec in
                    Text(((rec.newPath as NSString).lastPathComponent))
                        .strikethrough(rec.reverted)
                        .help(rec.newPath)
                }
                TableColumn("Category") { rec in
                    Text(categoryName(of: rec.newPath))
                        .foregroundStyle(.secondary)
                }
                TableColumn("Why") { rec in
                    HStack(spacing: 4) {
                        sourceBadge(rec.source)
                        Text(rec.reason ?? "—")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(rec.reason ?? "No reason recorded (legacy entry)")
                    }
                }
                .width(min: 220)
                TableColumn("When") { rec in
                    Text(rec.timestamp, style: .date) + Text(" ") + Text(rec.timestamp, style: .time)
                }
                .width(min: 110)
                TableColumn("Actions") { rec in
                    HStack(spacing: 4) {
                        if rec.source == "llm" && !rec.reverted {
                            Button {
                                suggestionTarget = rec
                            } label: {
                                Image(systemName: "wand.and.stars")
                            }
                            .buttonStyle(.borderless)
                            .help("Create a rule from this AI decision")
                            .foregroundStyle(.purple)
                        }

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: rec.newPath)])
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                        .disabled(rec.reverted)

                        if rec.reverted {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                mover.revert(rec)
                                refresh()
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .buttonStyle(.borderless)
                            .help("Revert to original location")
                        }
                    }
                }
                .width(min: 100)
            }
            .frame(minHeight: 320)
        }
        .padding(8)
        .onAppear { refresh() }
        .onReceive(mover.$recentMoves) { _ in refresh() }
        .sheet(item: $suggestionTarget) { rec in
            SuggestRuleSheet(record: rec, rulesStore: rulesStore)
        }
    }

    private func refresh() {
        allMoves = moveLog.recent(limit: 10_000)
    }

    private func categoryName(of path: String) -> String {
        let parts = path.components(separatedBy: "/")
        // .../AI Library/<Category>/<filename>
        if let idx = parts.lastIndex(of: "AI Library"), idx + 1 < parts.count - 1 {
            return parts[idx + 1]
        }
        return "—"
    }

    private func prettify(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func sourceBadge(_ src: String?) -> some View {
        let label: String
        let color: Color
        switch src {
        case "rule": label = "Rule"; color = .purple
        case "llm":  label = "AI";   color = .accentColor
        default:     label = "—";    color = .secondary
        }
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
