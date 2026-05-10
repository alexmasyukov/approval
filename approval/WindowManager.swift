//
//  WindowManager.swift
//  approval
//
//  Управляет per-request NSWindow для деталей команды. Один запрос —
//  одно окно. При нажатии Approve/Cancel в детали окно закрывается;
//  при ручном закрытии (через X) — запись из словаря снимается без
//  резолва (юзер просто закрыл инспектор).
//

import Foundation
import AppKit
import SwiftUI

@MainActor
final class WindowManager: NSObject {
    private var windows: [String: NSWindow] = [:]

    /// Инжектится из контейнера: нужен чтобы прокинуть L10n в окружение
    /// SwiftUI-окон (CommandDetailView читает локализацию).
    weak var l10n: L10n?

    /// Открывает окно деталей для запроса (или поднимает существующее
    /// если уже открыто). При клике Approve/Cancel вызывается
    /// `onResolve(approved)`; вызывающий код должен сам закрыть окно
    /// через closeWindow(id:).
    func openWindow(for cmd: PendingCommand, onResolve: @escaping (Bool) -> Void) {
        if let existing = windows[cmd.id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let l10n = self.l10n ?? L10n()
        let view = CommandDetailView(command: cmd, onResolve: onResolve)
            .environmentObject(l10n)
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

        windows[cmd.id] = window
    }

    func closeWindow(id: String) {
        guard let window = windows.removeValue(forKey: id) else { return }
        window.close()
    }
}

extension WindowManager: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            // Если окно закрыли через X, оно само вызывает windowWillClose;
            // нужно убрать запись из словаря, чтобы повторный тап по
            // уведомлению создал новое окно.
            for (id, w) in self.windows where w === window {
                self.windows.removeValue(forKey: id)
                break
            }
        }
    }
}
