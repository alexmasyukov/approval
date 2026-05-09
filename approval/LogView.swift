//
//  LogView.swift
//  approval
//

import SwiftUI

struct LogView: View {
    @EnvironmentObject var log: LogStore

    var body: some View {
        Form {
            Section("Информация") {
                LabeledContent("Записей", value: "\(log.entries.count) / 100")
                Button(role: .destructive) {
                    log.clear()
                } label: {
                    Text("Очистить лог")
                }
                .disabled(log.entries.isEmpty)
            }

            Section("История запросов") {
                if log.entries.isEmpty {
                    Text("пока пусто — здесь появятся команды, попавшие под фильтр")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.entries) { entry in
                        logRow(entry)
                    }
                }
            }

            Section("Файл") {
                Text(log.logFilePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Лог")
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
        Label(decision.label, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.bold())
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
