//
//  WindowManager.swift
//  approval
//
//  Управляет per-request NSWindow для деталей команды. Один запрос —
//  одно окно. Approve/Cancel из детали резолвят запрос; закрытие
//  окна крестиком трактуется как Cancel.
//

import Foundation
import AppKit
import SwiftUI

@MainActor
final class WindowManager: NSObject {
    private final class Entry {
        let window: NSWindow
        let onResolve: (Bool) -> Void
        var didResolve: Bool = false
        init(window: NSWindow, onResolve: @escaping (Bool) -> Void) {
            self.window = window
            self.onResolve = onResolve
        }
    }

    private var entries: [String: Entry] = [:]

    /// Инжектится из контейнера: нужен чтобы прокинуть L10n в окружение
    /// SwiftUI-окон (CommandDetailView читает локализацию).
    weak var l10n: L10n?

    /// Открывает окно деталей для запроса (или поднимает существующее
    /// если уже открыто). При клике Approve/Cancel вызывается
    /// `onResolve(approved)`; то же самое (с false) — при закрытии
    /// окна крестиком, если решение ещё не было принято.
    func openWindow(for cmd: PendingCommand, onResolve: @escaping (Bool) -> Void) {
        if let existing = entries[cmd.id] {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Создаём NSWindow с пустым placeholder-view, чтобы Entry
        // мог захватить ссылку на window, а замыкание-обёртка resolve —
        // на сам Entry. После — подменяем rootView на CommandDetailView,
        // которое уже зовёт обёртку.
        let hosting = NSHostingController(rootView: AnyView(EmptyView()))
        let window = NSWindow(contentViewController: hosting)
        let entry = Entry(window: window, onResolve: onResolve)

        let wrappedResolve: (Bool) -> Void = { [weak entry] approved in
            // Отмечаем что resolve уже произошёл, чтобы windowWillClose
            // не позвал onResolve(false) повторно.
            entry?.didResolve = true
            onResolve(approved)
        }

        let l10n = self.l10n ?? L10n()
        hosting.rootView = AnyView(
            CommandDetailView(command: cmd, onResolve: wrappedResolve)
                .environmentObject(l10n)
        )

        window.title = "Запрос подтверждения"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 460))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        entries[cmd.id] = entry
    }

    func closeWindow(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.window.close()
    }
}

extension WindowManager: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            for (id, entry) in self.entries where entry.window === window {
                if !entry.didResolve {
                    // Закрыли крестиком до явного решения — трактуем как Cancel.
                    entry.onResolve(false)
                }
                self.entries.removeValue(forKey: id)
                break
            }
        }
    }
}
