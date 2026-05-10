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
    private let saveQueue = DispatchQueue(label: "approval.log-store.save", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    private let saveDebounceMs = 500

    init() {
        self.fileURL = AppPaths.logFileURL

        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let loaded = try? decoder.decode([LogEntry].self, from: data) {
                self.entries = loaded
            } else {
                print("LogStore: failed to decode \(fileURL.path), starting fresh")
            }
        }
    }

    func append(_ entry: LogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        scheduleSave()
    }

    func updateDecision(id: String, decision: LogDecision) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].decision = decision
        entries[idx].resolvedAt = Date()
        scheduleSave()
    }

    func clear() {
        entries.removeAll()
        // Очистку сохраняем сразу, без debounce, чтобы файл не уехал
        // обратно при следующей записи если юзер закроет приложение.
        flushNow()
    }

    var logFilePath: String {
        fileURL.path
    }

    /// Debounced async save. Многократные вызовы в течение 500мс
    /// сольются в один write на background queue.
    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = entries
        let url = fileURL
        let work = DispatchWorkItem {
            Self.writeToDisk(entries: snapshot, url: url)
        }
        pendingSave = work
        saveQueue.asyncAfter(deadline: .now() + .milliseconds(saveDebounceMs), execute: work)
    }

    private func flushNow() {
        pendingSave?.cancel()
        let snapshot = entries
        let url = fileURL
        saveQueue.async {
            Self.writeToDisk(entries: snapshot, url: url)
        }
    }

    private static func writeToDisk(entries: [LogEntry], url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            print("LogStore: write failed: \(error)")
        }
    }
}
