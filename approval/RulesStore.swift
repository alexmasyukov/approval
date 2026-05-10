//
//  RulesStore.swift
//  approval
//

import Foundation
import Combine

@MainActor
final class RulesStore: ObservableObject {
    @Published var config: RulesConfig

    private let fileURL: URL
    private let saveQueue = DispatchQueue(label: "approval.rules-store.save", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    private let saveDebounceMs = 300

    convenience init() {
        self.init(fileURL: AppPaths.rulesFileURL)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                self.config = try JSONDecoder().decode(RulesConfig.self, from: data)
                return
            } catch {
                print("RulesStore: failed to load \(fileURL.path) (\(error)); using defaults")
                // Fallthrough на дефолт + перезапись.
            }
        }
        self.config = .defaultConfig
        // Первая запись — синхронно, чтобы файл точно был на диске
        // прежде чем кто-то его читает.
        Self.writeToDisk(config: self.config, url: fileURL)
    }

    func evaluate(command: String) -> Rule? {
        if config.mode == .passThrough { return nil }
        for rule in config.rules where rule.enabled {
            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive])
            } catch {
                print("RulesStore: invalid regex in rule '\(rule.name)' [\(rule.pattern)]: \(error); skipping")
                continue
            }
            let range = NSRange(command.startIndex..<command.endIndex, in: command)
            if regex.firstMatch(in: command, options: [], range: range) != nil {
                return rule
            }
        }
        return nil
    }

    func addRule(_ rule: Rule) {
        config.rules.append(rule)
        scheduleSave()
    }

    func removeRule(id: String) {
        config.rules.removeAll { $0.id == id }
        scheduleSave()
    }

    func toggleRule(id: String) {
        if let idx = config.rules.firstIndex(where: { $0.id == id }) {
            config.rules[idx].enabled.toggle()
            scheduleSave()
        }
    }

    func updateRule(_ rule: Rule) {
        if let idx = config.rules.firstIndex(where: { $0.id == rule.id }) {
            config.rules[idx] = rule
            scheduleSave()
        }
    }

    func setMode(_ mode: AppMode) {
        config.mode = mode
        scheduleSave()
    }

    /// Синхронная запись текущего состояния. Вызывать из
    /// applicationWillTerminate, чтобы не потерять последний batch
    /// изменений, ещё не сброшенный с дебаунса.
    func flushSync() {
        pendingSave?.cancel()
        pendingSave = nil
        Self.writeToDisk(config: config, url: fileURL)
    }

    var rulesFilePath: String {
        fileURL.path
    }

    /// Debounced async save. Многократные вызовы в течение
    /// `saveDebounceMs` сольются в один write на background queue.
    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = config
        let url = fileURL
        let work = DispatchWorkItem {
            Self.writeToDisk(config: snapshot, url: url)
        }
        pendingSave = work
        saveQueue.asyncAfter(deadline: .now() + .milliseconds(saveDebounceMs), execute: work)
    }

    private nonisolated static func writeToDisk(config: RulesConfig, url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(config)
            try data.write(to: url, options: .atomic)
        } catch {
            print("RulesStore: persist failed: \(error)")
        }
    }
}
