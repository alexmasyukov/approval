//
//  LogView.swift
//  approval
//

import SwiftUI
import AppKit

struct LogView: View {
    @EnvironmentObject var log: LogStore
    @EnvironmentObject var l10n: L10n
    @State private var showClearConfirm = false

    var body: some View {
        Form {
            Section(l10n.tr("log.section.info")) {
                LabeledContent(l10n.tr("log.entries_count"), value: "\(log.entries.count) / 100")
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Text(l10n.tr("log.clear_button"))
                }
                .disabled(log.entries.isEmpty)
            }

            Section(l10n.tr("log.section.file")) {
                LabeledContent(l10n.tr("log.path")) {
                    Text(log.logFilePath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button(l10n.tr("common.open_folder")) {
                    let url = URL(fileURLWithPath: log.logFilePath)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }

            Section(l10n.tr("log.section.history")) {
                if log.entries.isEmpty {
                    Text(l10n.tr("log.empty"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.entries) { entry in
                        logRow(entry)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.tr("log.title"))
        .confirmationDialog(l10n.tr("log.clear_confirm.title"),
                            isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            Button(l10n.tr("common.clear"), role: .destructive) {
                log.clear()
            }
            Button(l10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(l10n.tr("log.clear_confirm.message"))
        }
    }

    @ViewBuilder
    private func logRow(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                decisionBadge(entry.decision)
                Text(timeFormatter.string(from: entry.timestamp))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.ruleName)
                    .font(.callout)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }

            Text(entry.command)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                if let cwd = entry.cwd, !cwd.isEmpty {
                    Label(cwd, systemImage: "folder")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(entry.source)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func decisionBadge(_ decision: LogDecision) -> some View {
        let (color, symbol) = badgeStyle(for: decision)
        Label(l10n.tr(decision.labelKey), systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.callout.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }

    private func badgeStyle(for decision: LogDecision) -> (Color, String) {
        switch decision {
        case .pending:   return (.orange, "clock")
        case .approved:  return (.green, "checkmark.circle.fill")
        case .denied:    return (.red, "xmark.circle.fill")
        case .dismissed: return (.gray, "xmark")
        }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "dd.MM HH:mm:ss"
        return f
    }
}
