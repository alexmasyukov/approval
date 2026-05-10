//
//  CommandDetailView.swift
//  approval
//

import SwiftUI

struct CommandDetailView: View {
    let command: PendingCommand
    let onResolve: (Bool) -> Void

    @EnvironmentObject var l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("⚠️ " + l10n.tr("detail.title"))
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.tr("detail.field.source"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(command.source).font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.tr("detail.field.command"))
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    Text(command.command)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color.gray.opacity(0.15))
                .cornerRadius(6)
                .frame(maxHeight: 120)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.tr("detail.field.reason"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(command.reason)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                Button(l10n.tr("detail.button.cancel")) { onResolve(false) }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(l10n.tr("detail.button.approve")) { onResolve(true) }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }
}
