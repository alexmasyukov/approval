//
//  SettingsView.swift
//  approval
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(DefaultsKeys.verboseNotifications) private var verboseNotifications: Bool = true
    @EnvironmentObject var l10n: L10n

    var body: some View {
        Form {
            Section(l10n.tr("settings.section.notifications")) {
                Toggle(l10n.tr("settings.verbose_toggle"), isOn: $verboseNotifications)
                Text(verboseNotifications
                     ? l10n.tr("settings.verbose_on")
                     : l10n.tr("settings.verbose_off"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(l10n.tr("settings.section.preview")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verboseNotifications
                         ? l10n.tr("notif.verbose.title")
                         : l10n.tr("notif.minimal.title"))
                        .font(.body.bold())
                    Text(verboseNotifications
                         ? l10n.tr("notif.verbose.body")
                         : l10n.tr("notif.minimal.body"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(l10n.tr("settings.section.language")) {
                Picker(l10n.tr("settings.language.label"), selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text("\(lang.flag)  \(lang.displayName)").tag(lang)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.tr("settings.title"))
    }
}
