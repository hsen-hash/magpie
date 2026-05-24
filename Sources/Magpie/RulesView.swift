import SwiftUI
import AppKit

struct RulesView: View {
    @ObservedObject var store: RulesStore

    @State private var newPattern: String = ""
    @State private var newMatchType: CategorizationRule.MatchType = .glob
    @State private var newCategory: String = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            addRuleRow
            Divider()
            rulesList
        }
        .padding(8)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rules").font(.title2).bold()
                Text("Filenames matching a rule skip the LLM entirely — instant categorization, no API spend. First match wins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.openInEditor()
            } label: {
                Label("Edit rules.json", systemImage: "doc.text")
            }
            .controlSize(.small)
        }
    }

    private var addRuleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Pattern (e.g. *.dmg)", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                Picker("", selection: $newMatchType) {
                    ForEach(CategorizationRule.MatchType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                TextField("Category (e.g. Software)", text: $newCategory)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160)

                Button {
                    addRule()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .keyboardShortcut(.return)
                .disabled(newPattern.isEmpty || newCategory.isEmpty)
            }
            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("Glob: `*.dmg`, `Screenshot *.png`, `IMG_*.jpeg`   ·   Regex: case-insensitive, NSRegularExpression syntax")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var rulesList: some View {
        Group {
            if store.rules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No rules yet").font(.headline)
                    Text("Add a rule above to start short-circuiting the LLM for filenames you already know how to file.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.rules) { rule in
                            ruleRow(rule)
                        }
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: CategorizationRule) -> some View {
        let hits = store.hitsThisSession[rule.id] ?? 0
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { newVal in
                    var r = rule; r.enabled = newVal; store.update(r)
                }
            ))
            .labelsHidden()

            Text(rule.pattern)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: 240, alignment: .leading)
                .strikethrough(!rule.enabled)
                .foregroundStyle(rule.enabled ? .primary : .secondary)

            Text(rule.matchType.label)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.18), in: Capsule())

            Image(systemName: "arrow.right").foregroundStyle(.secondary).font(.caption)

            Text(rule.category)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.18), in: Capsule())

            Spacer()

            if hits > 0 {
                Text("\(hits) hit\(hits == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }

            Button { store.move(id: rule.id, direction: -1) } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .help("Move up")
            .disabled(store.rules.first?.id == rule.id)

            Button { store.move(id: rule.id, direction: 1) } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.borderless)
            .help("Move down")
            .disabled(store.rules.last?.id == rule.id)

            Button {
                store.remove(id: rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete rule")
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func addRule() {
        let pattern = newPattern.trimmingCharacters(in: .whitespaces)
        let category = newCategory.trimmingCharacters(in: .whitespaces)
        if let err = CategorizationRule.validate(pattern: pattern, matchType: newMatchType) {
            validationError = err
            return
        }
        if category.isEmpty {
            validationError = "Category is empty"
            return
        }
        validationError = nil
        store.add(CategorizationRule(
            pattern: pattern,
            matchType: newMatchType,
            category: category
        ))
        newPattern = ""
        newCategory = ""
    }
}
