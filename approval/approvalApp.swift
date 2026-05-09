//
//  approvalApp.swift
//  approval
//
//  Created by alex on 09.05.26.
//

import SwiftUI
import UserNotifications
import AppKit

@main
struct approvalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct PendingCommand: Equatable, Identifiable {
    let id: String
    let source: String
    let command: String
    let reason: String
}

struct ApprovalResult {
    let id: String
    let approved: Bool
}

extension Notification.Name {
    static let commandApprovalResult = Notification.Name("commandApprovalResult")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var detailWindows: [String: NSWindow] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error.localizedDescription)")
            }
            print("Notifications granted: \(granted)")
        }

        let category = UNNotificationCategory(
            identifier: "COMMAND_APPROVAL",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
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

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            DispatchQueue.main.async { [weak self] in
                self?.openDetailWindow(for: cmd)
            }
        case UNNotificationDismissActionIdentifier:
            NotificationCenter.default.post(
                name: .commandApprovalResult,
                object: ApprovalResult(id: id, approved: false)
            )
        default:
            break
        }
        completionHandler()
    }

    func openDetailWindow(for cmd: PendingCommand) {
        if let existing = detailWindows[cmd.id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = CommandDetailView(command: cmd) { [weak self] approved in
            self?.resolveCommand(id: cmd.id, approved: approved)
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Запрос подтверждения"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 580, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        detailWindows[cmd.id] = window
    }

    func resolveCommand(id: String, approved: Bool) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        NotificationCenter.default.post(
            name: .commandApprovalResult,
            object: ApprovalResult(id: id, approved: approved)
        )
        if let window = detailWindows[id] {
            window.close()
            detailWindows.removeValue(forKey: id)
        }
    }
}
