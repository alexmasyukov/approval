//
//  approvalApp.swift
//  approval
//

import SwiftUI
import AppKit

/// Дёргает все stores/координатор/сервер и держит их пока живо приложение.
/// Тут единственное место, где они инстанцируются.
@MainActor
final class AppContainer {
    let rules: RulesStore
    let pending: PendingStore
    let log: LogStore
    let notifications: NotificationClient
    let windows: WindowManager
    let coordinator: ApprovalCoordinator
    let server: ApprovalServer
    let l10n: L10n

    init() {
        let rules = RulesStore()
        let pending = PendingStore()
        let log = LogStore()
        let notifications = NotificationClient()
        let windows = WindowManager()
        let l10n = L10n()
        let coordinator = ApprovalCoordinator(
            pending: pending,
            log: log,
            notifications: notifications,
            windows: windows,
            l10n: l10n
        )
        let server = ApprovalServer(
            rules: rules,
            pending: pending,
            log: log,
            coordinator: coordinator
        )

        self.rules = rules
        self.pending = pending
        self.log = log
        self.notifications = notifications
        self.windows = windows
        self.l10n = l10n
        self.coordinator = coordinator
        self.server = server

        // NotificationClient тоже нужен L10n для текста уведомлений и
        // auth-статуса. Передаём через свойство, не через init —
        // чтобы не тянуть L10n в конструктор каждой UI-зависимой вещи.
        notifications.l10n = l10n
        windows.l10n = l10n
    }

    func bootstrap() {
        coordinator.setup()
        server.start()
    }

    func shutdown() {
        log.flushSync()
        server.stop()
    }
}

struct approvalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.container.rules)
                .environmentObject(appDelegate.container.pending)
                .environmentObject(appDelegate.container.log)
                .environmentObject(appDelegate.container.notifications)
                .environmentObject(appDelegate.container.coordinator)
                .environmentObject(appDelegate.container.server)
                .environmentObject(appDelegate.container.l10n)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: AppContainer

    override init() {
        // AppDelegate инстанцируется до Scene'ов; контейнер создаётся
        // здесь, чтобы и AppDelegate, и WindowGroup могли его читать.
        // MainActor гарантирован для NSApplicationDelegate-инициализации.
        self.container = MainActor.assumeIsolated { AppContainer() }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        container.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
