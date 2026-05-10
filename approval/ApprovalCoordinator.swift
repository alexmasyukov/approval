//
//  ApprovalCoordinator.swift
//  approval
//
//  Оркестратор approval-флоу: связывает NotificationClient (системные
//  уведомления), WindowManager (окна деталей), PendingStore (висящие
//  HTTP-запросы) и LogStore (история решений).
//
//  Сам ничего не рендерит и не лезет в UN/AppKit — для этого есть
//  NotificationClient и WindowManager. UI-state (lastResult/lastError)
//  публикуется через @Published и читается во вьюхах через
//  EnvironmentObject.
//

import Foundation
import Combine
import AppKit

@MainActor
final class ApprovalCoordinator: ObservableObject {
    /// Ключ результата ("result.approved" / "result.denied" / "result.dash").
    /// View рендерит через l10n.tr(coordinator.lastResultKey).
    @Published var lastResultKey: String = "result.dash"

    private let pending: PendingStore
    private let log: LogStore
    private let notifications: NotificationClient
    private let windows: WindowManager
    private let l10n: L10n

    init(
        pending: PendingStore,
        log: LogStore,
        notifications: NotificationClient,
        windows: WindowManager,
        l10n: L10n
    ) {
        self.pending = pending
        self.log = log
        self.notifications = notifications
        self.windows = windows
        self.l10n = l10n
    }

    func setup() {
        notifications.setup()
        notifications.onTap = { [weak self] cmd in
            self?.openDetailWindow(for: cmd)
        }
        notifications.onDismiss = { [weak self] id in
            self?.resolve(id: id, approved: false)
        }
    }

    // MARK: - External entry points

    func requestApproval(for cmd: PendingCommand) {
        // Direct mode: окно сразу + активация приложения, без системного
        // уведомления. UI-toggle в Settings → "Сразу показывать окно".
        let direct = UserDefaults.standard.bool(forKey: DefaultsKeys.directConfirmation)
        if direct {
            openDetailWindow(for: cmd)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            notifications.send(for: cmd)
        }
    }

    func resolve(id: String, approved: Bool) {
        notifications.remove(id: id)
        pending.resolve(id: id, approved: approved)
        log.updateDecision(id: id, decision: approved ? .approved : .denied)
        windows.closeWindow(id: id)
        lastResultKey = approved ? "result.approved" : "result.denied"
    }

    func openDetailWindow(for cmd: PendingCommand) {
        windows.openWindow(for: cmd) { [weak self] approved in
            self?.resolve(id: cmd.id, approved: approved)
        }
    }
}
