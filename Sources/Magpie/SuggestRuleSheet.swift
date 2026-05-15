import SwiftUI
import AppKit

struct SuggestRuleSheet: View {
    let record: MoveRecord
    @ObservedObject var rulesStore: RulesStore
    @Environment(\.dismiss) private var dismiss

    @State private var pattern: String
    @State private var matchType: CategorizationRule.MatchType = .glob
    @State private var category: String
    @State private var validationError: String?

    init(record: MoveRecord, rulesStore: RulesStore) {
        self.record = record
        self.rulesStore = rulesStore
        let filename = (record.newPath as NSString).lastPathComponent
        _pattern = State(initialValue: RuleSuggester.suggest(filename: filename))
        let parts = record.newPath.components(separatedBy: "/")
        let cat = parts.firstIndex(of: "AI Library").flatMap { idx -> String? in
            idx + 1 < parts.count - 1 ? parts[idx + 1] : nil
        } ?? ""
        _category = State(initialValue: cat)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            Group {
                Text("Pattern").font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                HStack {
                    TextField("Pattern", text: $pattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Picker("", selection: $matchType) {
                        ForEach(CategorizationRule.MatchType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                Text("Suggested from filename — edit if you want a broader / tighter match.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Group {
                Text("Category").font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                TextField("Category", text: $category)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            previewBlock

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save rule") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Turn this AI decision into a rule")
                .font(.title3)
                .bold()
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                Text((record.newPath as NSString).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let reason = record.reason, !reason.isEmpty {
                Text("AI said: “\(reason)”")
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var previewBlock: some View {
        let testFilename = (record.newPath as NSString).lastPathComponent
        let rule = CategorizationRule(pattern: pattern, matchType: matchType, category: category)
        let matches = rule.matches(filename: testFilename)
        return HStack(spacing: 8) {
            Image(systemName: matches ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(matches ? Color.green : Color.red)
            Text(matches
                 ? "Would match this filename"
                 : "Doesn’t match this filename anymore — broaden the pattern")
                .font(.caption)
        }
    }

    private func save() {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        let c = category.trimmingCharacters(in: .whitespaces)
        if let err = CategorizationRule.validate(pattern: p, matchType: matchType) {
            validationError = err
            return
        }
        if c.isEmpty {
            validationError = "Category is empty"
            return
        }
        validationError = nil
        rulesStore.add(CategorizationRule(
            pattern: p,
            matchType: matchType,
            category: c
        ))
        dismiss()
    }
}
