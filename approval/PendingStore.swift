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

    func resolve(id: String, approved: Bool) {
        if let entry = entries.removeValue(forKey: id) {
            pending.removeAll { $0.id == id }
            entry.onResolve(approved)
        }
    }

    func get(id: String) -> PendingCommand? {
        entries[id]?.command
    }
}
