//
//  Models.swift
//  approval
//

import Foundation

struct PendingCommand: Equatable, Identifiable, Codable {
    let id: String
    let source: String
    let command: String
    let reason: String
}

enum AppMode: String, Codable, CaseIterable, Identifiable {
    // Канонические идентификаторы (внутренние и в JSON) — оставляем
    // английскими: validate / pass_through. На UI показываем label.
    case validate
    case passThrough = "pass_through"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .validate:   return "С проверкой и оповещениями"
        case .passThrough: return "Без проверки"
        }
    }
}

struct Rule: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var pattern: String
    var enabled: Bool
    var builtin: Bool

    init(id: String = UUID().uuidString, name: String, pattern: String, enabled: Bool = true, builtin: Bool = false) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.enabled = enabled
        self.builtin = builtin
    }
}

struct RulesConfig: Codable, Equatable {
    var mode: AppMode
    var rules: [Rule]

    static let defaultConfig = RulesConfig(
        mode: .validate,
        rules: [
            Rule(name: "DROP TABLE/DATABASE/SCHEMA",
                 pattern: "DROP\\s+(TABLE|DATABASE|SCHEMA|VIEW|INDEX)",
                 builtin: true),
            Rule(name: "TRUNCATE",
                 pattern: "TRUNCATE\\s+(TABLE\\s+)?\\w+",
                 builtin: true),
            Rule(name: "DELETE FROM …;",
                 pattern: "DELETE\\s+FROM\\s+\\w+\\s*;",
                 builtin: true),
            Rule(name: "rm -rf",
                 pattern: "\\brm\\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)",
                 builtin: true),
            Rule(name: "psql/mysql -c с DROP/TRUNCATE/DELETE",
                 pattern: "(psql|mysql|mysqldump).*-c.*(DROP|TRUNCATE|DELETE\\s+FROM)",
                 builtin: true),
            Rule(name: "ALTER TABLE … DROP COLUMN",
                 pattern: "ALTER\\s+TABLE\\s+\\w+\\s+DROP\\s+COLUMN",
                 builtin: true),
            Rule(name: "mongo .drop()/dropDatabase()",
                 pattern: "\\.(drop|dropDatabase|deleteMany)\\s*\\(",
                 builtin: true),
            Rule(name: "redis FLUSHALL/FLUSHDB",
                 pattern: "\\b(FLUSHALL|FLUSHDB)\\b",
                 builtin: true),
        ]
    )
}
