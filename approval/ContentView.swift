//
//  ContentView.swift
//  approval
//

import SwiftUI
import UserNotifications
import AppKit

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case status = "Статус"
    case general = "Общие"
    case rules = "Правила"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .status:  return "shield.lefthalf.filled"
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

            Section("Активные запросы (\(pending.pending.count))") {
                if pending.pending.isEmpty {
                    Text("нет").foregroundStyle(.secondary)
                } else {
                    ForEach(pending.pending) { cmd in
                        HStack {
                            Text(cmd.command)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Button("Открыть") {
                                coordinator.openDetailWindow(for: cmd)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            Section("Тест") {
                LabeledContent("Последний ответ", value: coordinator.lastResult)
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
            coordinator.lastResult = "Pass-through — пропущено без вопроса"
            return
        }
        guard let matched = store.evaluate(command: command) else {
            coordinator.lastResult = "Совпадений нет — пропущено"
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

            Рабочая директория: /Users/alex/my-pro/myapp
            """
        )
        PendingStore.shared.add(cmd) { _ in }
        coordinator.requestApproval(for: cmd)
    }
}
