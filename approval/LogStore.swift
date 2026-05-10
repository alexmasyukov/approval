//
//  LogStore.swift
//  approval
//

import Foundation
import Combine

enum LogDecision: String, Codable, CaseIterable {
    case pending
    case approved
    case denied
    case dismissed

    var label: String {
        switch self {
        case .pending: return "ожидание"
        case .approved: return "подтверждено"
        case .denied: return "отменено"
        case .dismissed: return "закрыто"
        }
    }
}

struct LogEntry: Identifiable, Codable, Equatable {
    var id: String
    var timestamp: Date
    var command: String
    var source: String
    var cwd: String?
    var ruleName: String
    var rulePattern: String
    var decision: LogDecision
    var resolvedAt: Date?
}

@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [LogEntry] = []

    private let fileURL: URL
    private let maxEntries = 100

    init() {
        self.fileURL = AppPaths.logFileURL

        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let loaded = try? decoder.decode([LogEntry].self, from: data) {
                self.entries = loaded
            }
        }
    }

    func append(_ entry: LogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func updateDecision(id: String, decision: LogDecision) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].decision = decision
        entries[idx].resolvedAt = Date()
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    var logFilePath: String {
        fileURL.path
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
