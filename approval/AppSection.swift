//
//  AppSection.swift
//  approval
//
//  Список вкладок в сайдбаре.
//

import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case status, log, rules, install, general

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .status:  return "shield.lefthalf.filled"
        case .log:     return "list.bullet.clipboard"
        case .rules:   return "list.bullet.rectangle"
        case .install: return "arrow.down.app"
        case .general: return "gearshape"
        }
    }

    /// Ключ для L10n.
    var titleKey: String {
        switch self {
        case .status:  return "sidebar.status"
        case .log:     return "sidebar.log"
        case .rules:   return "sidebar.rules"
        case .install: return "sidebar.install"
        case .general: return "sidebar.settings"
        }
    }
}
