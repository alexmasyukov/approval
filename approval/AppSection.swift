//
//  AppSection.swift
//  approval
//
//  Список вкладок в сайдбаре.
//

import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case status = "Статус"
    case log = "Лог"
    case rules = "Правила"
    case install = "Установка хука"
    case general = "Настройки"

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
}
