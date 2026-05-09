//
//  RulesView.swift
//  approval
//

import SwiftUI

struct RulesView: View {
    @EnvironmentObject var store: RulesStore

    @State private var newName: String = ""
    @State private var newPattern: String = ""
    @State private var addError: String = ""

    var body: some View {
        Form {
            Section("Правила (\(store.config.rules.count))") {
                ForEach(store.config.rules) { rule in
                    ruleRow(rule)
                }
            }

            Section("Добавить правило") {
                TextField("Название", text: $newName)
                TextField("Regex (например: DROP\\s+TABLE)", text: $newPattern)
                    .font(.system(.body, design: .monospaced))
                if !addError.isEmpty {
                    Text(addError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Добавить") { addRule() }
                    .disabled(newName.isEmpty || newPattern.isEmpty)
            }

            Section("Файл с правилами") {
                Text(store.rulesFilePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Правила")
    }

    @ViewBuilder
    private func ruleRow(_ rule: Rule) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in store.toggleRule(id: rule.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.name)
                    if rule.builtin {
                        Text("builtin")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                Text(rule.pattern)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !rule.builtin {
                Button(role: .destructive) {
                    store.removeRule(id: rule.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func addRule() {
        if (try? NSRegularExpression(pattern: newPattern, options: [.caseInsensitive])) == nil {
            addError = "Невалидный regex"
            return
        }
        addError = ""
        store.addRule(Rule(name: newName, pattern: newPattern, enabled: true, builtin: false))
        newName = ""
        newPattern = ""
    }
}
