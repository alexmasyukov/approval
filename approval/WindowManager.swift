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
        init(window: NSWindow, onResolve: @escaping (Bool) -> Void) {
            self.window = window
            self.onResolve = onResolve
        }
    }

    /// Активные окна. Удаление из словаря — единственный сигнал
    /// «запрос уже отрезолвлен», флага didResolve нет.
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
            NSApp.activate()
            return
        }

        // Создаём NSWindow с пустым placeholder-view, чтобы wrappedResolve
        // мог захватить cmd.id и self для атомарного removeValue.
        let hosting = NSHostingController(rootView: AnyView(EmptyView()))
        let window = NSWindow(contentViewController: hosting)
        let entry = Entry(window: window, onResolve: onResolve)

        // Атомарность: removeValue либо сработает (тогда мы единственные,
        // кто вызовет onResolve), либо вернёт nil (значит windowWillClose
        // или другой путь нас опередил — выходим без вызова).
        let id = cmd.id
        let wrappedResolve: (Bool) -> Void = { [weak self] approved in
            guard let removed = self?.entries.removeValue(forKey: id) else { return }
            removed.onResolve(approved)
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
        NSApp.activate()

        entries[cmd.id] = entry
    }

    func closeWindow(id: String) {
        // Удаляем из словаря заранее — чтобы windowWillClose от close()
        // ниже увидел отсутствие entry и не позвал onResolve(false).
        // Сам resolve уже отработал через wrappedResolve выше по стеку.
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.window.close()
    }
}

extension WindowManager: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            // Ищем entry по ссылке на NSWindow. Если нашли — пользователь
            // закрыл окно крестиком/⌘W до явного решения, трактуем как Cancel.
            // Если не нашли — wrappedResolve или closeWindow(id:) уже отработали.
            var matchedID: String?
            for (id, entry) in self.entries where entry.window === window {
                matchedID = id
                break
            }
            guard let id = matchedID,
                  let entry = self.entries.removeValue(forKey: id) else {
                return
            }
            entry.onResolve(false)
        }
    }
}
