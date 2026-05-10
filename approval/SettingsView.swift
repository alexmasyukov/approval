//
//  SettingsView.swift
//  approval
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(DefaultsKeys.verboseNotifications) private var verboseNotifications: Bool = true
    @AppStorage(DefaultsKeys.showInMenuBar) private var showInMenuBar: Bool = false
    @AppStorage(DefaultsKeys.hideDockIcon) private var hideDockIcon: Bool = false
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

            Section(l10n.tr("settings.section.appearance")) {
                Toggle(l10n.tr("settings.menubar.toggle"), isOn: $showInMenuBar)
                    .onChange(of: showInMenuBar) { _, newValue in
                        // Защита от lock-out: без menu-bar нельзя прятать Dock,
                        // иначе доступ к приложению пропадёт.
                        if !newValue { hideDockIcon = false }
                    }
                Text(l10n.tr("settings.menubar.description"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(l10n.tr("settings.dock.toggle"), isOn: $hideDockIcon)
                    .disabled(!showInMenuBar)
                Text(showInMenuBar
                     ? l10n.tr("settings.dock.description")
                     : l10n.tr("settings.dock.requires_menubar"))
                    .font(.callout)
                    .foregroundStyle(showInMenuBar ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
