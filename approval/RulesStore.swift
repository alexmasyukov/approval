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
        Self.persist(self.config, to: fileURL)
    }

    private static func persist(_ config: RulesConfig, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(config)
            try data.write(to: url, options: .atomic)
        } catch {
            print("RulesStore: persist failed: \(error)")
        }
    }

    func save() {
        Self.persist(config, to: fileURL)
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
        save()
    }

    func removeRule(id: String) {
        config.rules.removeAll { $0.id == id }
        save()
    }

    func toggleRule(id: String) {
        if let idx = config.rules.firstIndex(where: { $0.id == id }) {
            config.rules[idx].enabled.toggle()
            save()
        }
    }

    func updateRule(_ rule: Rule) {
        if let idx = config.rules.firstIndex(where: { $0.id == rule.id }) {
            config.rules[idx] = rule
            save()
        }
    }

    func setMode(_ mode: AppMode) {
        config.mode = mode
        save()
    }

    var rulesFilePath: String {
        fileURL.path
    }
}
