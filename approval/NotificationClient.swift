//
//  NotificationClient.swift
//  approval
//
//  Тонкая обёртка над UNUserNotificationCenter. Вся работа с системными
//  уведомлениями (категории, авторизация, отправка, обработка ответа)
//  изолирована здесь.
//

import Foundation
import UserNotifications
import AppKit
import Combine

@MainActor
final class NotificationClient: NSObject, ObservableObject {
    @Published private(set) var authStatusKey: String = "auth.not_determined"
    @Published var lastError: String = ""

    /// Инжектится из AppContainer после создания.
    weak var l10n: L10n?

    var authStatus: String {
        l10n?.tr(authStatusKey) ?? authStatusKey
    }

    /// Колбэки, которые дёргаются когда пользователь решил судьбу
    /// уведомления (тапнул, отклонил, нажал action). Установить из
    /// ApprovalCoordinator при инициализации контейнера.
    var onTap: ((PendingCommand) -> Void)?
    var onDismiss: ((String) -> Void)?

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // .timeSensitive — иначе macOS даунгрейдит interruptionLevel
        // до .active и нотификация может задерживаться Focus-режимом.
        center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive]) { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.lastError = "Ошибка авторизации: \(error.localizedDescription)"
                }
                print("Notifications granted: \(granted)")
                self?.refreshAuthStatus()
            }
        }

        let category = UNNotificationCategory(
            identifier: NotificationConstants.categoryID,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])

        refreshAuthStatus()
    }

    func refreshAuthStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let key: String
            switch settings.authorizationStatus {
            case .notDetermined: key = "auth.not_determined"
            case .denied:        key = "auth.denied"
            case .authorized:    key = "auth.authorized"
            case .provisional:   key = "auth.provisional"
            case .ephemeral:     key = "auth.ephemeral"
            @unknown default:    key = "auth.unknown"
            }
            DispatchQueue.main.async {
                self?.authStatusKey = key
            }
        }
    }

    /// Отправляет системное уведомление. Текст зависит от настройки
    /// "Подробные оповещения" в UserDefaults.
    func send(for cmd: PendingCommand) {
        let verbose = UserDefaults.standard.object(forKey: DefaultsKeys.verboseNotifications) as? Bool ?? true

        let content = UNMutableNotificationContent()
        let lang = l10n
        if verbose {
            content.title = lang?.tr("notif.verbose.title") ?? "⚠️ Approval"
            content.body = lang?.tr("notif.verbose.body") ?? "Confirmation required"
        } else {
            content.title = lang?.tr("notif.minimal.title") ?? "Approval"
            content.body = lang?.tr("notif.minimal.body") ?? "Confirmation required"
        }
        content.categoryIdentifier = NotificationConstants.categoryID
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            "source": cmd.source,
            "command": cmd.command,
            "reason": cmd.reason
        ]

        let request = UNNotificationRequest(identifier: cmd.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.lastError = "Ошибка отправки оповещения: \(error.localizedDescription)"
                    print("notify error: \(error)")
                }
            }
        }
    }

    func remove(id: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(SystemURLs.notificationSettings)
    }
}

extension NotificationClient: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let id = response.notification.request.identifier
        let cmd = PendingCommand(
            id: id,
            source: info["source"] as? String ?? "—",
            command: info["command"] as? String ?? "—",
            reason: info["reason"] as? String ?? "—"
        )
        let action = response.actionIdentifier

        Task { @MainActor in
            switch action {
            case UNNotificationDefaultActionIdentifier:
                self.onTap?(cmd)
            case UNNotificationDismissActionIdentifier:
                self.onDismiss?(id)
            default:
                break
            }
            completionHandler()
        }
    }
}
