//
//  ContentView.swift
//  approval
//
//  Корень UI: NavigationSplitView с сайдбаром (AppSection) и
//  switch'ем по выбранной странице. Сами страницы — в отдельных
//  файлах (StatusView.swift, LogView.swift, RulesView.swift,
//  InstallView.swift, SettingsView.swift).
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var notifications: NotificationClient
    @EnvironmentObject var l10n: L10n

    @State private var selection: AppSection? = .status

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, id: \.self, selection: $selection) { section in
                Label(l10n.tr(section.titleKey), systemImage: section.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(200)
            .navigationTitle("approval")
        } detail: {
            Group {
                switch selection ?? .status {
                case .status:  StatusView()
                case .log:     LogView()
                case .rules:   RulesView()
                case .install: InstallView()
                case .general: GeneralSettingsView()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            notifications.refreshAuthStatus()
        }
    }
}
