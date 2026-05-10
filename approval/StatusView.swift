//
//  StatusView.swift
//  approval
//

import SwiftUI

struct StatusView: View {
    @EnvironmentObject var coordinator: ApprovalCoordinator
    @EnvironmentObject var notifications: NotificationClient
    @EnvironmentObject var server: ApprovalServer
    @EnvironmentObject var pending: PendingStore
    @EnvironmentObject var store: RulesStore
    @EnvironmentObject var log: LogStore
    @EnvironmentObject var l10n: L10n

    var body: some View {
        Form {
            if store.config.mode == .passThrough {
                passThroughBanner
            }

            Section(l10n.tr("status.section.server")) {
                LabeledContent(l10n.tr("status.server.state")) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(server.isRunning ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(server.isRunning
                             ? l10n.tr("status.server.listening")
                             : l10n.tr("status.server.stopped"))
                    }
                }
                if !server.lastError.isEmpty {
                    Text(server.lastError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            modeSection

            Section(l10n.tr("status.section.notifications")) {
                LabeledContent(l10n.tr("status.notifications.status"), value: notifications.authStatus)
                Button(l10n.tr("status.notifications.refresh")) { notifications.refreshAuthStatus() }
                Button(l10n.tr("status.notifications.open_settings")) { notifications.openSystemSettings() }
                if !notifications.lastError.isEmpty {
                    Text(notifications.lastError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section(l10n.tr("status.section.test")) {
                Text(l10n.tr("status.test.disclaimer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(l10n.tr("status.test.drop")) {
                    fireLocal(command: "DROP TABLE users; DROP TABLE orders;")
                }
                Button(l10n.tr("status.test.rm")) {
                    fireLocal(command: "rm -rf /tmp/foo")
                }
                Button(l10n.tr("status.test.select")) {
                    fireLocal(command: "SELECT * FROM users LIMIT 10")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.tr("status.title"))
    }

    @ViewBuilder
    private var passThroughBanner: some View {
        Section {
            WarningBanner(
                title: l10n.tr("status.passthrough.banner_title"),
                message: l10n.tr("status.passthrough.banner_message")
            )
        }
        .warningBackground()
    }

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: Binding(
                get: { store.config.mode },
                set: { store.setMode($0) }
            )) {
                ForEach(AppMode.allCases) { m in
                    Text(l10n.tr(m.labelKey)).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text(l10n.tr("status.section.mode"))
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
            \(l10n.tr("rule.field.name")): \(matched.name)
            \(l10n.tr("rule.field.regex")): \(matched.pattern)
            """
        )
        log.append(LogEntry(
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
        pending.add(cmd) { _ in }
        coordinator.requestApproval(for: cmd)
    }
}
