//
//  PendingStore.swift
//  approval
//

import Foundation
import Combine

@MainActor
final class PendingStore: ObservableObject {
    struct Entry {
        let command: PendingCommand
        let onResolve: (Bool) -> Void
        let createdAt: Date
    }

    @Published private(set) var pending: [PendingCommand] = []
    private var entries: [String: Entry] = [:]

    func add(_ command: PendingCommand, onResolve: @escaping (Bool) -> Void) {
        entries[command.id] = Entry(command: command, onResolve: onResolve, createdAt: Date())
        pending.append(command)
    }

    /// Возвращает true, если запрос реально был отрезолвлен этим вызовом.
    /// Повторные вызовы (например, timeout сработал после Approve/Cancel)
    /// возвращают false и не дёргают onResolve повторно — caller'у
    /// удобно по этому флагу решать, надо ли посылать ответ хуку.
    @discardableResult
    func resolve(id: String, approved: Bool) -> Bool {
        guard let entry = entries.removeValue(forKey: id) else { return false }
        pending.removeAll { $0.id == id }
        entry.onResolve(approved)
        return true
    }

    func get(id: String) -> PendingCommand? {
        entries[id]?.command
    }
}
