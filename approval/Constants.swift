//
//  Constants.swift
//  approval
//
//  Централизованные константы и helper-пути.
//  Если меняешь имя файла, ID нотификации или ключ UserDefaults —
//  меняй здесь, не охотясь по всему проекту.
//

import Foundation

// MARK: - Application Support paths

enum AppPaths {
    /// Имя директории внутри ~/Library/Application Support/.
    static let dirName = "approval"

    /// Имена файлов в этой директории.
    static let rulesFileName = "rules.json"
    static let logFileName = "log.json"
    static let socketFileName = "approval.sock"

    /// `~/Library/Application Support/approval/` — создаётся при первом обращении.
    static var dataDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(dirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var rulesFileURL: URL { dataDirectory.appendingPathComponent(rulesFileName) }
    static var logFileURL: URL { dataDirectory.appendingPathComponent(logFileName) }
    static var socketPath: String { dataDirectory.appendingPathComponent(socketFileName).path }
}

// MARK: - Notification

enum NotificationConstants {
    /// ID категории UNNotificationCategory для запросов approval.
    static let categoryID = "COMMAND_APPROVAL"
}

// MARK: - UserDefaults keys

enum DefaultsKeys {
    /// Bool, по умолчанию true. Полный текст vs короткий в системном уведомлении.
    static let verboseNotifications = "verboseNotifications"

    /// Идентификатор языка UI ("ru" или "en"). По умолчанию "ru".
    static let appLanguage = "appLanguage"

    /// Bool. Показывать ли иконку в строке меню (menu bar). По умолчанию false.
    static let showInMenuBar = "showInMenuBar"

    /// Bool. Скрывать ли иконку в Dock (через `.accessory` activation policy).
    /// По умолчанию false.
    static let hideDockIcon = "hideDockIcon"

    /// Bool. Если true — пропускаем системное уведомление и сразу
    /// открываем окно подтверждения с активацией приложения. По умолчанию false.
    static let directConfirmation = "directConfirmation"
}

// MARK: - System URLs

enum SystemURLs {
    /// macOS Settings → Notifications.
    static let notificationSettings = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
}

// MARK: - IPC protocol

enum IPCProtocol {
    /// Источник по умолчанию для запросов от Claude Code.
    static let defaultSource = "Claude Code"

    /// Таймаут чтения/записи на стороне хука (секунды).
    static let hookTimeoutSeconds = 600
}
