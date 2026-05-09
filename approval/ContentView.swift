//
//  ContentView.swift
//  approval
//

import SwiftUI
import UserNotifications
import AppKit

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case status = "Статус"
    case log = "Лог"
    case general = "Общие"
    case rules = "Правила"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .status:  return "shield.lefthalf.filled"
        case .log:     return "list.bullet.clipboard"
        case .general: return "gearshape"
        case .rules:   return "list.bullet.rectangle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var coordinator: ApprovalCoordinator

    @State private var selection: AppSection? = .status

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, id: \.self, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .navigationTitle("approval")
        } detail: {
            Group {
                switch selection ?? .status {
                case .status:  StatusView()
                case .log:     LogView()
                case .general: GeneralSettingsView()
                case .rules:   RulesView()
                }
            }
            .navigationSplitViewColumnWidth(min: 520, ideal: 720)
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            coordinator.refreshAuthStatus()
        }
    }
}

struct StatusView: View {
    @EnvironmentObject var coordinator: ApprovalCoordinator
    @EnvironmentObject var server: ApprovalServer
    @EnvironmentObject var pending: PendingStore
    @EnvironmentObject var store: RulesStore

    var body: some View {
        Form {
            Section("Сервер") {
                LabeledContent("Состояние") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(server.isRunning ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(server.isRunning ? "слушает" : "не запущен")
                    }
                }
                if server.isRunning {
                    LabeledContent("Адрес") {
                        Text("http://localhost:\(server.port)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                if !server.lastError.isEmpty {
                    Text(server.lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Уведомления") {
                LabeledContent("Статус", value: coordinator.authStatus)
                Button("Обновить статус") { coordinator.refreshAuthStatus() }
                Button("Открыть настройки уведомлений") { coordinator.openNotificationSettings() }
                if !coordinator.lastError.isEmpty {
                    Text(coordinator.lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Режим работы") {
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

                if store.config.mode == .passThrough {
                    Label("Все команды проходят без проверки", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout.bold())
                }
            }

            Section("Тест") {
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

    private func fireLocal(command: String) {
        if store.config.mode == .passThrough {
            return
        }
        guard let matched = store.evaluate(command: command) else {
            return
        }
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
