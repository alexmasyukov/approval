//
//  StatusView.swift
//  approval
//

import SwiftUI

struct StatusView: View {
    @EnvironmentObject var coordinator: ApprovalCoordinator
    @EnvironmentObject var server: ApprovalServer
    @EnvironmentObject var pending: PendingStore
    @EnvironmentObject var store: RulesStore

    var body: some View {
        Form {
            if store.config.mode == .passThrough {
                passThroughBanner
            }

            Section("Сервер") {
                LabeledContent("Состояние") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(server.isRunning ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(server.isRunning ? "слушает" : "не запущен")
                    }
                }
                if !server.lastError.isEmpty {
                    Text(server.lastError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            modeSection

            Section("Уведомления MacOS") {
                LabeledContent("Статус", value: coordinator.authStatus)
                Button("Обновить статус") { coordinator.refreshAuthStatus() }
                Button("Открыть настройки уведомлений") { coordinator.openNotificationSettings() }
                if !coordinator.lastError.isEmpty {
                    Text(coordinator.lastError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("Тестирование оповещений") {
                Button("Тест: DROP TABLE users") {
                    fireLocal(command: "DROP TABLE users; DROP TABLE orders;")
                }
                Button("Тест: rm -rf /tmp/foo") {
                    fireLocal(command: "rm -rf /tmp/foo")
                }
                Button("Тест: SELECT (безопасно)") {
                    fireLocal(command: "SELECT * FROM users LIMIT 10")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Статус")
    }

    @ViewBuilder
    private var passThroughBanner: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Режим «Без проверки» включён")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("Все команды Claude Code проходят без проверки. Не забудь переключить обратно в «С проверкой и оповещениями».")
                        .font(.callout)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red, lineWidth: 2)
                )
        )
    }

    private var modeSection: some View {
        Section {
            Picker("Режим", selection: Binding(
                get: { store.config.mode },
                set: { store.setMode($0) }
            )) {
                ForEach(AppMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Режим работы")
                .foregroundStyle(store.config.mode == .passThrough ? .red : .primary)
        }
    }

    private func fireLocal(command: String) {
        if store.config.mode == .passThrough { return }
        guard let matched = store.evaluate(command: command) else { return }

        let id = UUID().uuidString
        let cmd = PendingCommand(
            id: id,
            source: "Test trigger (in-app)",
            command: command,
            reason: """
            Совпадение с правилом: \(matched.name)
            Паттерн: \(matched.pattern)
            """
        )
        LogStore.shared.append(LogEntry(
            id: id,
            timestamp: Date(),
            command: command,
            source: "Test trigger (in-app)",
            cwd: nil,
            ruleName: matched.name,
            rulePattern: matched.pattern,
            decision: .pending,
            resolvedAt: nil
        ))
        PendingStore.shared.add(cmd) { _ in }
        coordinator.requestApproval(for: cmd)
    }
}
