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

    /// L10n-ключ для UI-надписи. Сама строка резолвится через L10n.tr().
    var labelKey: String {
        switch self {
        case .validate:   return "mode.validate"
        case .passThrough: return "mode.passthrough"
        }
    }
}

struct Rule: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var pattern: String
    var enabled: Bool

    init(id: String = UUID().uuidString, name: String, pattern: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.enabled = enabled
    }
}

struct RulesConfig: Codable, Equatable {
    var mode: AppMode
    var rules: [Rule]

    static let defaultConfig = RulesConfig(
        mode: .validate,
        rules: [
            Rule(name: "DROP TABLE/DATABASE/SCHEMA",
                 pattern: "DROP\\s+(TABLE|DATABASE|SCHEMA|VIEW|INDEX)"),
            Rule(name: "TRUNCATE",
                 pattern: "TRUNCATE\\s+(TABLE\\s+)?\\w+"),
            Rule(name: "DELETE FROM …;",
                 pattern: "DELETE\\s+FROM\\s+\\w+\\s*;"),
            Rule(name: "rm -rf",
                 pattern: "\\brm\\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)"),
            Rule(name: "psql/mysql -c с DROP/TRUNCATE/DELETE",
                 pattern: "(psql|mysql|mysqldump).*-c.*(DROP|TRUNCATE|DELETE\\s+FROM)"),
            Rule(name: "ALTER TABLE … DROP COLUMN",
                 pattern: "ALTER\\s+TABLE\\s+\\w+\\s+DROP\\s+COLUMN"),
            Rule(name: "mongo .drop()/dropDatabase()",
                 pattern: "\\.(drop|dropDatabase|deleteMany)\\s*\\("),
            Rule(name: "redis FLUSHALL/FLUSHDB",
                 pattern: "\\b(FLUSHALL|FLUSHDB)\\b"),
            Rule(name: "rm SQLite/DB файла",
                 pattern: "\\brm\\b[^|;&]*\\.(sqlite3?|db)\\b"),
            Rule(name: "sqlite3 с DROP/DELETE",
                 pattern: "\\bsqlite3\\b.*(DROP\\s+(TABLE|DATABASE|SCHEMA|VIEW|INDEX)|DELETE\\s+FROM|TRUNCATE)"),
            Rule(name: "mongosh dropDatabase/drop",
                 pattern: "\\bmongo(sh)?\\b.*--eval.*(drop|dropDatabase|deleteMany)"),
            Rule(name: "dropdb / mysqladmin drop",
                 pattern: "\\b(dropdb\\b|mysqladmin\\s+(drop|flush-hosts|shutdown))"),
            Rule(name: "docker volume/compose destructive",
                 pattern: "\\bdocker(-compose)?\\s+(volume\\s+rm|down[^|;&]*\\s-v|rm\\s+[^|;&]*-[a-zA-Z]*f)"),
            Rule(name: "find … -delete/-exec rm",
                 pattern: "\\bfind\\b[^|;&]*(-delete\\b|-exec\\s+rm\\b)"),
            Rule(name: "Truncate через редирект/cp /dev/null",
                 pattern: "(>\\s*\\S+\\.(sqlite3?|db)\\b|\\bcp\\s+/dev/null\\s+\\S+\\.(sqlite3?|db)\\b)"),
            Rule(name: "DROP USER/ROLE / REVOKE",
                 pattern: "\\bDROP\\s+(USER|ROLE|GROUP)\\b|\\bREVOKE\\s+(ALL|ALL\\s+PRIVILEGES)\\b"),
            Rule(name: "mongoimport/mongorestore --drop",
                 pattern: "\\b(mongoimport|mongorestore)\\b[^|;&]*--drop\\b"),
        ]
    )
}
