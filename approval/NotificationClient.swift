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
    @Published private(set) var authStatus: String = "не запрошено"
    @Published var lastError: String = ""

    /// Колбэки, которые дёргаются когда пользователь решил судьбу
    /// уведомления (тапнул, отклонил, нажал action). Установить из
    /// ApprovalCoordinator при инициализации контейнера.
    var onTap: ((PendingCommand) -> Void)?
    var onDismiss: ((String) -> Void)?

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
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
            let text: String
            switch settings.authorizationStatus {
            case .notDetermined: text = "не запрошено"
            case .denied: text = "запрещено ❌"
            case .authorized: text = "разрешено ✅"
            case .provisional: text = "временно (provisional)"
            case .ephemeral: text = "ephemeral"
            @unknown default: text = "неизвестно"
            }
            DispatchQueue.main.async {
                self?.authStatus = text
            }
        }
    }

    /// Отправляет системное уведомление. Текст зависит от настройки
    /// "Подробные оповещения" в UserDefaults.
    func send(for cmd: PendingCommand) {
        let verbose = UserDefaults.standard.object(forKey: DefaultsKeys.verboseNotifications) as? Bool ?? true

        let content = UNMutableNotificationContent()
        if verbose {
            content.title = "⚠️ Запрос на подтверждение опасной команды"
            content.body = "Claude Code хочет выполнить деструктивную операцию. Откройте оповещение, чтобы посмотреть детали и подтвердить или отменить."
        } else {
            content.title = "Approval"
            content.body = "Требуется подтверждение"
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
