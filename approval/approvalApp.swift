//
//  approvalApp.swift
//  approval
//

import SwiftUI
import AppKit

struct approvalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(RulesStore.shared)
                .environmentObject(PendingStore.shared)
                .environmentObject(ApprovalCoordinator.shared)
                .environmentObject(ApprovalServer.shared)
                .environmentObject(LogStore.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ApprovalCoordinator.shared.setup()
        ApprovalServer.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Сбросить debounced log на диск, иначе последняя запись потеряется.
        LogStore.shared.flushSync()
        // Снять unix socket с диска.
        ApprovalServer.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
