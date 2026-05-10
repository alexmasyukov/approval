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
    case rules = "Правила"
    case install = "Установка хука"
    case general = "Настройки"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .status:  return "shield.lefthalf.filled"
        case .log:     return "list.bullet.clipboard"
        case .rules:   return "list.bullet.rectangle"
        case .install: return "arrow.down.app"
        case .general: return "gearshape"
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
            .navigationSplitViewColumnWidth(200)
            .navigationTitle("approval")
        } detail: {
            Group {
                switch selection ?? .status {
                case .status:  StatusView()
                case .log:     LogView()
                case .rules:   RulesView()
                case .install: InstallView()
                case .general: GeneralSettingsView()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
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

    @State private var showPortAlert = false
    @State private var portInput: String = ""
    @State private var portError: String = ""

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
                        Text(verbatim: "http://localhost:\(server.port)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                Button("Изменить порт") {
                    portInput = "\(server.port)"
                    portError = ""
                    showPortAlert = true
                }
                if !server.lastError.isEmpty {
                    Text(server.lastError)
                        .font(.callout)
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

            Section("Уведомления") {
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
        .alert("Изменить порт сервера", isPresented: $showPortAlert) {
            TextField("Порт (1-65535)", text: $portInput)
            Button("Применить") {
                applyPortChange()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сервер перезапустится на новом порту.\(portError.isEmpty ? "" : "\n\n\(portError)")")
        }
    }

    private func applyPortChange() {
        let trimmed = portInput.trimmingCharacters(in: .whitespaces)
        guard let p = Int(trimmed), p > 0, p <= 65535 else {
            portError = "Введите число от 1 до 65535"
            showPortAlert = true
            return
        }
        portError = ""
        server.setPort(UInt16(p))
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
