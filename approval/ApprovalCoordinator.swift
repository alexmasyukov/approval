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

@MainActor
final class ApprovalCoordinator: ObservableObject {
    @Published var lastResult: String = "—"

    private let pending: PendingStore
    private let log: LogStore
    private let notifications: NotificationClient
    private let windows: WindowManager

    init(
        pending: PendingStore,
        log: LogStore,
        notifications: NotificationClient,
        windows: WindowManager
    ) {
        self.pending = pending
        self.log = log
        self.notifications = notifications
        self.windows = windows
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
        notifications.send(for: cmd)
    }

    func resolve(id: String, approved: Bool) {
        notifications.remove(id: id)
        pending.resolve(id: id, approved: approved)
        log.updateDecision(id: id, decision: approved ? .approved : .denied)
        windows.closeWindow(id: id)
        lastResult = approved ? "Подтверждено ✅" : "Отменено ❌"
    }

    func openDetailWindow(for cmd: PendingCommand) {
        windows.openWindow(for: cmd) { [weak self] approved in
            self?.resolve(id: cmd.id, approved: approved)
        }
    }
}
