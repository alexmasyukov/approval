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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Режим:").font(.headline)
                Picker("", selection: Binding(
                    get: { store.config.mode },
                    set: { store.setMode($0) }
                )) {
                    ForEach(AppMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Spacer()

                if store.config.mode == .passThrough {
                    Label("ВНИМАНИЕ: пропускаются все команды", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .bold()
                }
            }

            Divider()

            Text("Правила (\(store.config.rules.count))").font(.headline)

            Table(store.config.rules) {
                TableColumn("On") { rule in
                    Toggle("", isOn: Binding(
                        get: { rule.enabled },
                        set: { _ in store.toggleRule(id: rule.id) }
                    ))
                    .labelsHidden()
                }
                .width(40)

                TableColumn("Имя") { rule in
                    HStack {
                        Text(rule.name)
                        if rule.builtin {
                            Text("builtin")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }

                TableColumn("Regex") { rule in
                    Text(rule.pattern).font(.system(.body, design: .monospaced))
                }

                TableColumn("") { rule in
                    Button(role: .destructive) {
                        store.removeRule(id: rule.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .width(40)
            }
            .frame(minHeight: 240)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Добавить правило").font(.headline)
                HStack {
                    TextField("Название", text: $newName).frame(width: 200)
                    TextField("Regex (например: DROP\\s+TABLE)", text: $newPattern)
                        .font(.system(.body, design: .monospaced))
                    Button("Добавить") {
                        addRule()
                    }
                    .disabled(newName.isEmpty || newPattern.isEmpty)
                }
                if !addError.isEmpty {
                    Text(addError).foregroundStyle(.red).font(.caption)
                }
            }

            Text("Файл с правилами: \(store.rulesFilePath)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(20)
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
