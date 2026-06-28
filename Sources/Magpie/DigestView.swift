import SwiftUI
import AppKit

struct DigestView: View {
    @ObservedObject var digest: DigestService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if digest.isRunning && digest.latest == nil {
                    runningPlaceholder
                } else if let d = digest.latest {
                    summaryCards(d)
                    if let narrative = d.narrative, !narrative.isEmpty {
                        narrativeSection(narrative, model: d.narrativeModel)
                    }
                    tipsSection(d)
                    if !d.byCategory.isEmpty { categorySection(d) }
                    if !d.largestNew.isEmpty { largestSection(d) }
                } else {
                    emptyState
                }

                if let err = digest.lastError {
                    Text("AI summary unavailable: \(err)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }
            }
            .padding(8)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily digest").font(.title2).bold()
                if let d = digest.latest {
                    Text("Generated \(d.generatedAt.formatted(date: .abbreviated, time: .shortened)) · covers since \(d.periodStart.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Runs automatically once a day. You can also scan on demand.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await digest.generate(background: false) }
            } label: {
                if digest.isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Scanning…")
                    }
                } else {
                    Label("Scan now", systemImage: "arrow.clockwise")
                }
            }
            .disabled(digest.isRunning)
        }
    }

    private var runningPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Scanning your folders…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No digest yet")
                .font(.headline)
            Text("Hit “Scan now” to get your first summary of recent activity and clutter.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func summaryCards(_ d: DailyDigest) -> some View {
        HStack(spacing: 12) {
            statCard(value: "\(d.filesFiled)", label: "Filed", detail: d.bytesFiled.humanBytes, color: .green)
            statCard(value: "\(d.stuckInRecents)", label: "In Recents", detail: d.stuckInRecents > 0 ? "needs rescue" : "clear", color: d.stuckInRecents > 0 ? .orange : .secondary)
            statCard(value: "\(d.duplicateGroups)", label: "Duplicate sets", detail: d.duplicateGroups > 0 ? "~\(d.reclaimableBytes.humanBytes)" : "none", color: d.duplicateGroups > 0 ? .red : .secondary)
        }
    }

    private func statCard(value: String, label: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title).bold().foregroundStyle(color)
            Text(label).font(.caption).bold()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func narrativeSection(_ text: String, model: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Summary", systemImage: "sparkles")
                .font(.caption).bold().foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let model {
                Text("Written by \(model)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func tipsSection(_ d: DailyDigest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How to keep it tidy", systemImage: "checklist")
                .font(.caption).bold().foregroundStyle(.secondary)
            ForEach(Array(d.tips.enumerated()), id: \.offset) { _, tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.tint)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(tip)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categorySection(_ d: DailyDigest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("New files by category", systemImage: "folder")
                .font(.caption).bold().foregroundStyle(.secondary)
            let maxCount = max(d.byCategory.first?.count ?? 1, 1)
            ForEach(d.byCategory) { row in
                HStack(spacing: 8) {
                    Text(row.category)
                        .font(.caption)
                        .frame(width: 130, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(0.5))
                            .frame(width: max(4, geo.size.width * CGFloat(row.count) / CGFloat(maxCount)))
                    }
                    .frame(height: 12)
                    Text("\(row.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }

    private func largestSection(_ d: DailyDigest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Largest new files", systemImage: "scalemass")
                .font(.caption).bold().foregroundStyle(.secondary)
            ForEach(d.largestNew) { f in
                HStack(spacing: 8) {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(f.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(f.bytes.humanBytes)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        let url = URL(fileURLWithPath: f.path)
                        if FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } else {
                            NSSound.beep()
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }
            }
        }
    }
}
