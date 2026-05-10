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

    var body: some View {
        Form {
            if store.config.mode == .passThrough {
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
                if store.config.mode == .passThrough {
                    Text("Режим работы")
                        .foregroundStyle(.red)
                } else {
                    Text("Режим работы")
                }
            }

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
