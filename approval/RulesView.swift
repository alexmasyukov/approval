//
//  RulesView.swift
//  approval
//

import SwiftUI
import AppKit

struct RulesView: View {
    @EnvironmentObject var store: RulesStore

    @State private var showAddSheet = false

    var body: some View {
        Form {
            Section("Правила (\(store.config.rules.count))") {
                ForEach(store.config.rules) { rule in
                    ruleRow(rule)
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("Добавить правило", systemImage: "plus")
                }
            }

            Section("Файл с правилами") {
                Text(store.rulesFilePath)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Открыть папку") {
                    let url = URL(fileURLWithPath: store.rulesFilePath)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Правила")
        .sheet(isPresented: $showAddSheet) {
            AddRuleSheet { rule in
                store.addRule(rule)
                showAddSheet = false
            } onCancel: {
                showAddSheet = false
            }
        }
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
}

struct AddRuleSheet: View {
    let onAdd: (Rule) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var pattern: String = ""
    @State private var error: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Новое правило")
                    .font(.headline)
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                Section {
                    LabeledContent("Название") {
                        TextField("Например: DROP TABLE", text: $name)
                    }
                    LabeledContent("Regex") {
                        TextField("DROP\\s+TABLE", text: $pattern)
                            .font(.system(.body, design: .monospaced))
                    }
                } footer: {
                    Text("Шаблон будет проверяться на команде регулярным выражением (case-insensitive). При совпадении приложение запросит подтверждение.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !error.isEmpty {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 220)

            Divider()

            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Добавить") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || pattern.isEmpty)
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private func submit() {
        guard (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) != nil else {
            error = "Невалидный regex"
            return
        }
        error = ""
        onAdd(Rule(name: name, pattern: pattern, enabled: true, builtin: false))
    }
}
