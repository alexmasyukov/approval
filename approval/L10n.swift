//
//  L10n.swift
//  approval
//
//  Простая локализация без xcstrings/lproj — таблица строк с ключами,
//  инжектится через @EnvironmentObject. Меняется на лету при переключении
//  языка в Настройках.
//
//  Будущее: когда понадобится больше языков — мигрировать на
//  Localizable.xcstrings и .environment(\.locale, ...) на корне.
//

import Foundation
import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru, en

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .ru: return "🇷🇺"
        case .en: return "🇬🇧"
        }
    }

    var displayName: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        }
    }
}

@MainActor
final class L10n: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: DefaultsKeys.appLanguage)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: DefaultsKeys.appLanguage) ?? AppLanguage.ru.rawValue
        self.language = AppLanguage(rawValue: saved) ?? .ru
    }

    /// Достать перевод по ключу. Если ключа нет в текущем языке — fallback на EN, потом сам ключ.
    func tr(_ key: String) -> String {
        return Self.strings[language]?[key]
            ?? Self.strings[.en]?[key]
            ?? key
    }

    /// Удобный shortcut для интерполяции одного аргумента в шаблон.
    func tr(_ key: String, _ args: CVarArg...) -> String {
        let template = tr(key)
        return String(format: template, arguments: args)
    }

    // MARK: - Translations table

    private static let strings: [AppLanguage: [String: String]] = [
        .ru: ru,
        .en: en,
    ]

    private static let ru: [String: String] = [
        // Sidebar
        "sidebar.status": "Статус",
        "sidebar.log": "Лог",
        "sidebar.rules": "Правила",
        "sidebar.install": "Установка хука",
        "sidebar.settings": "Настройки",

        // Common buttons
        "common.cancel": "Отмена",
        "common.add": "Добавить",
        "common.delete": "Удалить",
        "common.clear": "Очистить",
        "common.refresh": "Обновить",
        "common.open_folder": "Открыть папку",
        "common.copy": "Скопировать",
        "common.copy_all": "Скопировать всё",
        "common.copied": "Скопировано ✓",

        // Status page
        "status.title": "Статус",
        "status.section.server": "Сервер",
        "status.section.notifications": "Уведомления MacOS",
        "status.section.mode": "Режим работы",
        "status.section.test": "Тестирование оповещений",
        "status.server.state": "Состояние",
        "status.server.listening": "слушает",
        "status.server.stopped": "не запущен",
        "status.notifications.status": "Статус",
        "status.notifications.refresh": "Обновить статус",
        "status.notifications.open_settings": "Открыть настройки уведомлений",
        "status.test.drop": "Тест: DROP TABLE users",
        "status.test.rm": "Тест: rm -rf /tmp/foo",
        "status.test.select": "Тест: SELECT (безопасно)",
        "status.passthrough.banner_title": "Режим «Без проверки» включён",
        "status.passthrough.banner_message": "Все команды Claude Code проходят без проверки. Не забудь переключить обратно в «С проверкой и оповещениями».",

        // Notification auth statuses
        "auth.not_determined": "не запрошено",
        "auth.denied": "запрещено ❌",
        "auth.authorized": "разрешено ✅",
        "auth.provisional": "временно (provisional)",
        "auth.ephemeral": "ephemeral",
        "auth.unknown": "неизвестно",

        // Mode picker
        "mode.validate": "С проверкой и оповещениями",
        "mode.passthrough": "Без проверки",

        // Log page
        "log.title": "Лог",
        "log.section.info": "Информация",
        "log.section.history": "История запросов",
        "log.section.file": "Файл",
        "log.entries_count": "Записей",
        "log.clear_button": "Очистить лог",
        "log.empty": "пока пусто — здесь появятся команды, попавшие под фильтр",
        "log.path": "Путь",
        "log.clear_confirm.title": "Очистить лог?",
        "log.clear_confirm.message": "Все записи будут удалены без возможности восстановления.",
        "log.decision.pending": "ожидание",
        "log.decision.approved": "подтверждено",
        "log.decision.denied": "отменено",
        "log.decision.dismissed": "закрыто",

        // Rules page
        "rules.title": "Правила",
        "rules.section.list": "Правила",
        "rules.section.file": "Файл с правилами",
        "rules.add_button": "Добавить правило",
        "rules.builtin_badge": "builtin",

        // Add rule sheet
        "rule.new.title": "Новое правило",
        "rule.field.name": "Название",
        "rule.field.regex": "Regex",
        "rule.placeholder.name": "Например: DROP TABLE",
        "rule.placeholder.regex": "DROP\\s+TABLE",
        "rule.help.regex": "Шаблон проверяется регулярным выражением (case-insensitive). При совпадении с командой будет запрошено подтверждение.",
        "rule.error.invalid_regex": "Невалидный regex",

        // Detail window (Approve / Cancel)
        "detail.title": "Запрос на выполнение опасной команды",
        "detail.field.source": "Источник",
        "detail.field.command": "Команда",
        "detail.field.reason": "Обоснование / контекст",
        "detail.button.approve": "Подтвердить",
        "detail.button.cancel": "Отменить",

        // Settings page
        "settings.title": "Настройки",
        "settings.section.notifications": "Оповещения",
        "settings.section.preview": "Превью",
        "settings.section.language": "Язык интерфейса",
        "settings.verbose_toggle": "Подробные оповещения",
        "settings.verbose_on": "Полный заголовок и описание в системном уведомлении.",
        "settings.verbose_off": "Минимальный заголовок и короткое тело.",
        "settings.language.label": "Язык",

        // Notification body (verbose / minimal)
        "notif.verbose.title": "⚠️ Запрос на подтверждение опасной команды",
        "notif.verbose.body": "Claude Code хочет выполнить деструктивную операцию. Откройте оповещение, чтобы посмотреть детали и подтвердить или отменить.",
        "notif.minimal.title": "Approval",
        "notif.minimal.body": "Требуется подтверждение",

        // Last result
        "result.approved": "Подтверждено ✅",
        "result.denied": "Отменено ❌",
        "result.dash": "—",
        "result.label": "Последний ответ",
    ]

    private static let en: [String: String] = [
        // Sidebar
        "sidebar.status": "Status",
        "sidebar.log": "Log",
        "sidebar.rules": "Rules",
        "sidebar.install": "Install hook",
        "sidebar.settings": "Settings",

        // Common buttons
        "common.cancel": "Cancel",
        "common.add": "Add",
        "common.delete": "Delete",
        "common.clear": "Clear",
        "common.refresh": "Refresh",
        "common.open_folder": "Open folder",
        "common.copy": "Copy",
        "common.copy_all": "Copy all",
        "common.copied": "Copied ✓",

        // Status page
        "status.title": "Status",
        "status.section.server": "Server",
        "status.section.notifications": "macOS notifications",
        "status.section.mode": "Mode",
        "status.section.test": "Test notifications",
        "status.server.state": "State",
        "status.server.listening": "listening",
        "status.server.stopped": "not running",
        "status.notifications.status": "Status",
        "status.notifications.refresh": "Refresh status",
        "status.notifications.open_settings": "Open notification settings",
        "status.test.drop": "Test: DROP TABLE users",
        "status.test.rm": "Test: rm -rf /tmp/foo",
        "status.test.select": "Test: SELECT (safe)",
        "status.passthrough.banner_title": "Pass-through mode is on",
        "status.passthrough.banner_message": "All Claude Code commands run without confirmation. Don't forget to switch back to «Validate & notify».",

        // Notification auth statuses
        "auth.not_determined": "not determined",
        "auth.denied": "denied ❌",
        "auth.authorized": "authorized ✅",
        "auth.provisional": "provisional",
        "auth.ephemeral": "ephemeral",
        "auth.unknown": "unknown",

        // Mode picker
        "mode.validate": "Validate & notify",
        "mode.passthrough": "Pass-through",

        // Log page
        "log.title": "Log",
        "log.section.info": "Info",
        "log.section.history": "Request history",
        "log.section.file": "File",
        "log.entries_count": "Entries",
        "log.clear_button": "Clear log",
        "log.empty": "Empty — commands that match a filter will appear here",
        "log.path": "Path",
        "log.clear_confirm.title": "Clear log?",
        "log.clear_confirm.message": "All entries will be deleted permanently.",
        "log.decision.pending": "pending",
        "log.decision.approved": "approved",
        "log.decision.denied": "denied",
        "log.decision.dismissed": "dismissed",

        // Rules page
        "rules.title": "Rules",
        "rules.section.list": "Rules",
        "rules.section.file": "Rules file",
        "rules.add_button": "Add rule",
        "rules.builtin_badge": "builtin",

        // Add rule sheet
        "rule.new.title": "New rule",
        "rule.field.name": "Name",
        "rule.field.regex": "Regex",
        "rule.placeholder.name": "e.g. DROP TABLE",
        "rule.placeholder.regex": "DROP\\s+TABLE",
        "rule.help.regex": "The pattern is matched as a case-insensitive regular expression. When a command matches, you'll be asked to confirm.",
        "rule.error.invalid_regex": "Invalid regex",

        // Detail window (Approve / Cancel)
        "detail.title": "Dangerous command requires confirmation",
        "detail.field.source": "Source",
        "detail.field.command": "Command",
        "detail.field.reason": "Reason / context",
        "detail.button.approve": "Approve",
        "detail.button.cancel": "Cancel",

        // Settings page
        "settings.title": "Settings",
        "settings.section.notifications": "Notifications",
        "settings.section.preview": "Preview",
        "settings.section.language": "Interface language",
        "settings.verbose_toggle": "Verbose notifications",
        "settings.verbose_on": "Full title and body in the system notification.",
        "settings.verbose_off": "Minimal title and short body.",
        "settings.language.label": "Language",

        // Notification body (verbose / minimal)
        "notif.verbose.title": "⚠️ Dangerous command requires confirmation",
        "notif.verbose.body": "Claude Code wants to run a destructive command. Open this notification to see details and approve or cancel.",
        "notif.minimal.title": "Approval",
        "notif.minimal.body": "Confirmation required",

        // Last result
        "result.approved": "Approved ✅",
        "result.denied": "Cancelled ❌",
        "result.dash": "—",
        "result.label": "Last response",
    ]
}
