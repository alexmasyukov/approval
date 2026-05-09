//
//  ContentView.swift
//  approval
//

import SwiftUI
import UserNotifications
import AppKit

struct ContentView: View {
    @EnvironmentObject var coordinator: ApprovalCoordinator
    @EnvironmentObject var server: ApprovalServer
    @EnvironmentObject var pending: PendingStore
    @EnvironmentObject var store: RulesStore

    var body: some View {
        TabView {
            mainTab
                .tabItem { Label("Статус", systemImage: "shield.lefthalf.filled") }
            RulesView()
                .tabItem { Label("Правила", systemImage: "list.bullet.rectangle") }
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            coordinator.refreshAuthStatus()
        }
    }

    private var mainTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Approval").font(.largeTitle).bold()

            statusBlock
            modeBlock

            Divider()

            pendingBlock

            Divider()

            testBlock

            Spacer()
        }
        .padding(20)
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text("Сервер: ").bold()
                Text(server.isRunning ? "слушает на http://localhost:\(server.port)" : "не запущен")
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text("Notifications: ").bold()
                Text(coordinator.authStatus)
                Button("Обновить") { coordinator.refreshAuthStatus() }
                    .controlSize(.small)
                Button("Настройки уведомлений") { coordinator.openNotificationSettings() }
                    .controlSize(.small)
            }

            HStack {
                Text("Последний ответ: ").bold()
                Text(coordinator.lastResult).foregroundStyle(.secondary)
            }

            if !coordinator.lastError.isEmpty {
                Text(coordinator.lastError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if !server.lastError.isEmpty {
                Text(server.lastError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    private var modeBlock: some View {
        HStack {
            Text("Режим:").bold()
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
            .labelsHidden()

            if store.config.mode == .passThrough {
                Label("Все команды пропускаются!", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .bold()
            }
        }
    }

    private var pendingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Активные запросы (\(pending.pending.count))").font(.headline)
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
                        Button("Открыть") { coordinator.openDetailWindow(for: cmd) }
                            .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.12))
                    .cornerRadius(6)
                }
            }
        }
    }

    private var testBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Тест").font(.headline)
            HStack {
                Button("Тест: DROP TABLE users") {
                    fireLocal(command: "DROP TABLE users; DROP TABLE orders;",
                              source: "Test trigger (in-app)",
                              cwd: "/Users/alex/my-pro/myapp")
                }
                Button("Тест: rm -rf /tmp/foo") {
                    fireLocal(command: "rm -rf /tmp/foo",
                              source: "Test trigger (in-app)",
                              cwd: "/Users/alex/my-pro/myapp")
                }
                Button("Тест: SELECT (безопасно)") {
                    fireLocal(command: "SELECT * FROM users LIMIT 10",
                              source: "Test trigger (in-app)",
                              cwd: "/Users/alex/my-pro/myapp")
                }
            }
        }
    }

    private func fireLocal(command: String, source: String, cwd: String) {
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
            source: source,
            command: command,
            reason: """
            Совпадение с правилом: \(matched.name)
            Паттерн: \(matched.pattern)

            Рабочая директория: \(cwd)
            """
        )
        PendingStore.shared.add(cmd) { _ in
            // result already updated via coordinator.resolve → lastResult
        }
        coordinator.requestApproval(for: cmd)
    }
}
