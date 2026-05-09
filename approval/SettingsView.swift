//
//  SettingsView.swift
//  approval
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("verboseNotifications") private var verboseNotifications: Bool = true

    var body: some View {
        Form {
            Section("Оповещения") {
                Toggle("Подробные оповещения", isOn: $verboseNotifications)
                Text(verboseNotifications
                     ? "Полный заголовок и описание в системном уведомлении."
                     : "Минимальный заголовок и короткое тело.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Превью") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verboseNotifications
                         ? "⚠️ Запрос на подтверждение опасной команды"
                         : "Approval")
                        .font(.body.bold())
                    Text(verboseNotifications
                         ? "Claude Code хочет выполнить деструктивную операцию. Откройте оповещение, чтобы посмотреть детали и подтвердить или отменить."
                         : "Требуется подтверждение")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Настройки")
    }
}
