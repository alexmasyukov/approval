//
//  CommandDetailView.swift
//  approval
//

import SwiftUI

struct CommandDetailView: View {
    let command: PendingCommand
    let onResolve: (Bool) -> Void

    @EnvironmentObject var l10n: L10n

    /// Глобальный множитель размера шрифта в этом окне. 1.0 = 100%.
    /// Хранится в UserDefaults, шарится между всеми detail-окнами.
    @AppStorage(DefaultsKeys.detailFontScale) private var fontScale: Double = 1.0

    private static let minScale: Double = 0.7
    private static let maxScale: Double = 2.0
    private static let scaleStep: Double = 0.1

    var body: some View {
        VStack(alignment: .leading, spacing: 14 * fontScale) {
            HStack(alignment: .center) {
                Text("⚠️ " + l10n.tr("detail.title"))
                    .font(.system(size: 22 * fontScale, weight: .bold))
                Spacer()
                fontScaleControl
            }

            VStack(alignment: .leading, spacing: 6 * fontScale) {
                Text(l10n.tr("detail.field.source"))
                    .font(.system(size: 11 * fontScale))
                    .foregroundStyle(.secondary)
                Text(command.source)
                    .font(.system(size: 13 * fontScale, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6 * fontScale) {
                Text(l10n.tr("detail.field.command"))
                    .font(.system(size: 11 * fontScale))
                    .foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    Text(command.command)
                        .font(.system(size: 13 * fontScale, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color.gray.opacity(0.15))
                .cornerRadius(6)
                .frame(maxHeight: 120 * fontScale)
            }

            VStack(alignment: .leading, spacing: 6 * fontScale) {
                Text(l10n.tr("detail.field.reason"))
                    .font(.system(size: 11 * fontScale))
                    .foregroundStyle(.secondary)
                Text(command.reason)
                    .font(.system(size: 13 * fontScale))
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                Button(l10n.tr("detail.button.cancel")) { onResolve(false) }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(l10n.tr("detail.button.approve")) { onResolve(true) }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }

    /// Маленькая панелька «− 100% +» в правом верхнем углу окна.
    private var fontScaleControl: some View {
        HStack(spacing: 4) {
            Button {
                fontScale = max(Self.minScale, fontScale - Self.scaleStep)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 18)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(fontScale <= Self.minScale + 0.001)

            Text("\(Int(fontScale * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 38)

            Button {
                fontScale = min(Self.maxScale, fontScale + Self.scaleStep)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 18)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(fontScale >= Self.maxScale - 0.001)
        }
    }
}
