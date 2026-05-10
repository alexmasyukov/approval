//
//  ApprovalCoordinator.swift
//  approval
//

import Foundation
import UserNotifications
import AppKit
import SwiftUI
import Combine

@MainActor
final class ApprovalCoordinator: NSObject, ObservableObject {
    static let shared = ApprovalCoordinator()

    @Published var lastResult: String = "—"
    @Published var lastError: String = ""
    @Published var authStatus: String = "не запрошено"

    private var detailWindows: [String: NSWindow] = [:]

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

    func requestApproval(for cmd: PendingCommand) {
        sendNotification(for: cmd)
    }

    private func sendNotification(for cmd: PendingCommand) {
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

    func resolve(id: String, approved: Bool) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        PendingStore.shared.resolve(id: id, approved: approved)
        LogStore.shared.updateDecision(id: id, decision: approved ? .approved : .denied)
        if let w = detailWindows[id] {
            detailWindows.removeValue(forKey: id)
            w.close()
        }
        lastResult = approved ? "Подтверждено ✅" : "Отменено ❌"
    }

    func openDetailWindow(for cmd: PendingCommand) {
        if let existing = detailWindows[cmd.id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = CommandDetailView(command: cmd) { [weak self] approved in
            self?.resolve(id: cmd.id, approved: approved)
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Запрос подтверждения"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 460))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        detailWindows[cmd.id] = window
    }

    func openNotificationSettings() {
        NSWorkspace.shared.open(SystemURLs.notificationSettings)
    }
}

extension ApprovalCoordinator: UNUserNotificationCenterDelegate {
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
                self.openDetailWindow(for: cmd)
            case UNNotificationDismissActionIdentifier:
                self.resolve(id: id, approved: false)
            default:
                break
            }
            completionHandler()
        }
    }
}

extension ApprovalCoordinator: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            for (id, w) in self.detailWindows where w === window {
                self.detailWindows.removeValue(forKey: id)
                break
            }
        }
    }
}
