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

    // @AppStorage здесь, а не в @Published обёртке — биндинг $showInMenuBar
    // в MenuBarExtra(isInserted:) с ObservableObject вызывал бесконечный
    // цикл "Publishing changes from within view updates is not allowed".
    @AppStorage(DefaultsKeys.showInMenuBar) private var showInMenuBar: Bool = false

    var body: some Scene {
        // Window (а не WindowGroup) — это singleton-окно: повторный
        // openWindow(id:) фокусирует существующее, не создаёт дубль.
        Window("approval", id: "main") {
            ContentView()
                .environmentObject(appDelegate.container.rules)
                .environmentObject(appDelegate.container.pending)
                .environmentObject(appDelegate.container.log)
                .environmentObject(appDelegate.container.notifications)
                .environmentObject(appDelegate.container.coordinator)
                .environmentObject(appDelegate.container.server)
                .environmentObject(appDelegate.container.l10n)
        }

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarContent(
                l10n: appDelegate.container.l10n,
                pending: appDelegate.container.pending
            )
        } label: {
            MenuBarLabel(pending: appDelegate.container.pending)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var pending: PendingStore

    var body: some View {
        if pending.pending.isEmpty {
            Image(systemName: "staroflife.fill")
        } else {
            // Принудительный красный — чтобы заметно «прыгало» в menu bar.
            // Template-режим тут отключается: иконка не будет адаптироваться
            // к тёмной/светлой теме, но при pending это и нужно — внимание.
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var l10n: L10n
    @ObservedObject var pending: PendingStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !pending.pending.isEmpty {
            Text(l10n.tr("menubar.pending_count", String(pending.pending.count)))
            Divider()
        }
        Button(l10n.tr("menubar.open")) {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Divider()
        Button(l10n.tr("menubar.quit")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: AppContainer
    private var defaultsObserver: NSObjectProtocol?

    override init() {
        // AppDelegate инстанцируется до Scene'ов; контейнер создаётся
        // здесь, чтобы и AppDelegate, и WindowGroup могли его читать.
        self.container = MainActor.assumeIsolated { AppContainer() }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        container.bootstrap()
        MainActor.assumeIsolated {
            applyDockPolicyFromDefaults(activateIfRegular: false)
        }

        // Динамическая смена .accessory ↔ .regular без рестарта.
        // Слушаем UserDefaults — туда пишет @AppStorage в SettingsView.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyDockPolicyFromDefaults(activateIfRegular: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let obs = defaultsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        container.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    private func applyDockPolicyFromDefaults(activateIfRegular: Bool) {
        let hidden = UserDefaults.standard.bool(forKey: DefaultsKeys.hideDockIcon)
        let target: NSApplication.ActivationPolicy = hidden ? .accessory : .regular
        guard NSApp.activationPolicy() != target else { return }
        NSApp.setActivationPolicy(target)
        if !hidden && activateIfRegular {
            // После возврата из .accessory приложение бывает невидимым
            // в Cmd+Tab до явной активации. На старте этого делать
            // не нужно — система сама даст фокус GUI-приложению.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
