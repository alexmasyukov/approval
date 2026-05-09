//
//  ContentView.swift
//  approval
//
//  Created by alex on 09.05.26.
//

import SwiftUI
import UserNotifications
import AppKit

struct ContentView: View {
    @State private var lastResult: String = "—"
    @State private var authStatus: String = "не запрошено"
    @State private var lastError: String = ""

    var body: some View {
        VStack(spacing: 18) {
            Text("Approval")
                .font(.largeTitle)
                .bold()

            HStack(spacing: 8) {
                Text("Статус разрешения:")
                    .foregroundStyle(.secondary)
                Text(authStatus).bold()
            }

            Text("Последний ответ: \(lastResult)")
                .foregroundStyle(.secondary)

            if !lastError.isEmpty {
                Text(lastError)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Divider()

            Button("Запросить подтверждение команды") {
                requestApproval()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            HStack(spacing: 12) {
                Button("Запросить разрешение") { requestPermission() }
                Button("Обновить статус") { refreshStatus() }
                Button("Открыть настройки") { openNotificationSettings() }
            }
        }
        .padding(40)
        .frame(minWidth: 520, minHeight: 320)
        .onAppear { refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .commandApprovalResult)) { note in
            if let result = note.object as? ApprovalResult {
                lastResult = result.approved ? "Подтверждено ✅" : "Отменено ❌"
            }
        }
    }

    private func requestApproval() {
        lastError = ""
        let id = UUID().uuidString
        let source = "Claude Code session в /Users/alex/my-pro/myapp (PID 48123)"
        let command = "DROP TABLE users; DROP TABLE orders;"
        let reason = "Удаляю таблицы users и orders, чтобы пересоздать схему перед накатом миграций. Все данные будут безвозвратно потеряны."

        let content = UNMutableNotificationContent()
        content.title = "⚠️ Запрос на подтверждение опасной команды"
        content.body = "Claude Code хочет выполнить деструктивную операцию. Откройте оповещение, чтобы посмотреть детали и подтвердить или отменить."
        content.categoryIdentifier = "COMMAND_APPROVAL"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            "source": source,
            "command": command,
            "reason": reason
        ]

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    lastError = "Ошибка отправки: \(error.localizedDescription)"
                    print("Add notification error: \(error)")
                } else {
                    print("Notification scheduled: \(id)")
                }
            }
        }
    }

    private func requestPermission() {
        lastError = ""
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    lastError = "Ошибка авторизации: \(error.localizedDescription)"
                }
                print("Auth granted: \(granted)")
                refreshStatus()
            }
        }
    }

    private func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let text: String
            switch settings.authorizationStatus {
            case .notDetermined: text = "не запрошено"
            case .denied: text = "запрещено ❌"
            case .authorized: text = "разрешено ✅"
            case .provisional: text = "временно (provisional)"
            case .ephemeral: text = "ephemeral"
            @unknown default: text = "неизвестно"
            }
            DispatchQueue.main.async { authStatus = text }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct CommandDetailView: View {
    let command: PendingCommand
    let onResolve: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("⚠️ Запрос на выполнение опасной команды")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 6) {
                Text("Источник").font(.caption).foregroundStyle(.secondary)
                Text(command.source).font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Команда").font(.caption).foregroundStyle(.secondary)
                Text(command.command)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(6)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Обоснование").font(.caption).foregroundStyle(.secondary)
                Text(command.reason)
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                Button("Отменить") { onResolve(false) }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Подтвердить") { onResolve(true) }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 380)
    }
}

#Preview {
    ContentView()
}
