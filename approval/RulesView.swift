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
                    .font(.title3)
                    .bold()
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    formField(label: "Название") {
                        TextField("Например: DROP TABLE", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                    }

                    formField(label: "Regex") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextEditor(text: $pattern)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 120)
                                .padding(6)
                                .background(Color(NSColor.textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                                )
                                .cornerRadius(6)

                            Text("Шаблон проверяется регулярным выражением (case-insensitive). При совпадении с командой будет запрошено подтверждение.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !error.isEmpty {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                .padding(24)
            }

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
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 560, minHeight: 440)
    }

    @ViewBuilder
    private func formField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func submit() {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (try? NSRegularExpression(pattern: trimmedPattern, options: [.caseInsensitive])) != nil else {
            error = "Невалидный regex"
            return
        }
        error = ""
        onAdd(Rule(
            name: name.trimmingCharacters(in: .whitespaces),
            pattern: trimmedPattern,
            enabled: true,
            builtin: false
        ))
    }
}
