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

        if let data = try? Data(contentsOf: fileURL),
           let cfg = try? JSONDecoder().decode(RulesConfig.self, from: data) {
            self.config = cfg
        } else {
            self.config = .defaultConfig
            Self.persist(self.config, to: fileURL)
        }
    }

    private static func persist(_ config: RulesConfig, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func save() {
        Self.persist(config, to: fileURL)
    }

    func evaluate(command: String) -> Rule? {
        if config.mode == .passThrough { return nil }
        for rule in config.rules where rule.enabled {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else {
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
