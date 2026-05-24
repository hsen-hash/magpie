import SwiftUI

struct APIUsageView: View {
    let apiLog: ApiUsageLog

    @State private var totalsAllTime = ApiUsageTotals()
    @State private var totalsToday = ApiUsageTotals()
    @State private var totalsMonth = ApiUsageTotals()
    @State private var recent: [ApiUsageRecord] = []
    @State private var pricing = PricingTable()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("LLM consumption")
                    .font(.title2)
                    .bold()

                HStack(spacing: 12) {
                    summaryCard(title: "Today", t: totalsToday)
                    summaryCard(title: "Last 30 days", t: totalsMonth)
                    summaryCard(title: "All time", t: totalsAllTime)
                }

                Divider()

                Text("Pricing (cloud providers)")
                    .font(.headline)
                HStack(spacing: 24) {
                    pricingField(label: "Input $/1M tokens", value: $pricing.inputPerMillion)
                    pricingField(label: "Output $/1M tokens", value: $pricing.outputPerMillion)
                    Spacer()
                    Text("Ollama calls are always $0.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text("Recent calls")
                    .font(.headline)
                Table(recent) {
                    TableColumn("When") { rec in
                        Text(rec.timestamp, style: .date) + Text(" ") + Text(rec.timestamp, style: .time)
                    }
                    TableColumn("Provider") { rec in
                        providerBadge(rec.provider)
                    }
                    .width(min: 70, max: 90)
                    TableColumn("Model") { Text($0.model).font(.system(.body, design: .monospaced)) }
                    TableColumn("Files") { rec in
                        Text("\(rec.filenameCount)")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    TableColumn("Prompt tk") { rec in
                        Text("\(rec.promptTokens)")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    TableColumn("Output tk") { rec in
                        Text("\(rec.candidateTokens)")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    TableColumn("Est. cost") { rec in
                        Text(rec.isLocal
                             ? "$0"
                             : String(format: "$%.5f", pricing.cost(for: rec)))
                            .foregroundStyle(rec.isLocal ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    TableColumn("Status") { rec in
                        Text("\(rec.httpStatus)")
                            .foregroundStyle(rec.httpStatus < 300 ? .secondary : Color.red)
                    }
                }
                .frame(minHeight: 220)
            }
            .padding(8)
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .magpieApiUsageDidChange)) { _ in
            refresh()
        }
    }

    private func summaryCard(title: String, t: ApiUsageTotals) -> some View {
        let cost = pricing.cost(for: t)
        let isAllLocal = t.calls > 0
            && t.localPromptTokens == t.promptTokens
            && t.localCandidateTokens == t.candidateTokens
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
            if isAllLocal {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("$0")
                        .font(.title)
                        .bold()
                    Text("local")
                        .font(.caption)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.18), in: Capsule())
                        .foregroundStyle(.green)
                }
            } else {
                Text(String(format: "$%.4f", cost))
                    .font(.title)
                    .bold()
            }
            Text("\(t.calls) call\(t.calls == 1 ? "" : "s") · \(t.filenamesProcessed) file\(t.filenamesProcessed == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(t.promptTokens.formatted()) in · \(t.candidateTokens.formatted()) out")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func pricingField(label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(2)))
                .frame(width: 70)
        }
    }

    private func providerBadge(_ provider: String) -> some View {
        let (label, color): (String, Color)
        switch CategorizerProvider(rawValue: provider) {
        case .ollama:
            (label, color) = ("Ollama", .green)
        case .gemini:
            (label, color) = ("Gemini", .accentColor)
        case .none:
            (label, color) = (provider.capitalized, .secondary)
        }
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private func refresh() {
        let cal = Calendar.current
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now

        totalsAllTime = apiLog.totals()
        totalsToday = apiLog.totals(since: startOfDay)
        totalsMonth = apiLog.totals(since: thirtyDaysAgo)
        recent = apiLog.recent(limit: 100)
    }
}
