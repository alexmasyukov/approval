//
//  approvalApp.swift
//  approval
//

import SwiftUI
import AppKit

@main
struct approvalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(RulesStore.shared)
                .environmentObject(PendingStore.shared)
                .environmentObject(ApprovalCoordinator.shared)
                .environmentObject(ApprovalServer.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ApprovalCoordinator.shared.setup()
        ApprovalServer.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
