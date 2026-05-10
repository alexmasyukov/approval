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
    let coordinator: ApprovalCoordinator
    let server: ApprovalServer

    init() {
        let rules = RulesStore()
        let pending = PendingStore()
        let log = LogStore()
        let coordinator = ApprovalCoordinator(pending: pending, log: log)
        let server = ApprovalServer(
            rules: rules,
            pending: pending,
            log: log,
            coordinator: coordinator
        )

        self.rules = rules
        self.pending = pending
        self.log = log
        self.coordinator = coordinator
        self.server = server
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
                .environmentObject(appDelegate.container.coordinator)
                .environmentObject(appDelegate.container.server)
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
