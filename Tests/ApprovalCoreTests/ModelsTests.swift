import XCTest
@testable import ApprovalCore

final class ModelsTests: XCTestCase {

    func test_appMode_rawValuesStableForJSON() {
        XCTAssertEqual(AppMode.validate.rawValue, "validate")
        XCTAssertEqual(AppMode.passThrough.rawValue, "pass_through")
    }

    func test_appMode_codableRoundTrip() throws {
        for mode in AppMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(AppMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func test_rule_codableRoundTrip() throws {
        let original = Rule(
            id: UUID().uuidString,
            name: "Test",
            pattern: "DROP\\s+TABLE",
            enabled: true,
            builtin: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Rule.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_rulesConfig_codableRoundTrip() throws {
        let original = RulesConfig(
            mode: .validate,
            rules: [
                Rule(name: "A", pattern: "a", enabled: true, builtin: true),
                Rule(name: "B", pattern: "b", enabled: false, builtin: false),
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RulesConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_defaultConfig_hasBuiltinRulesEnabledInValidateMode() {
        let cfg = RulesConfig.defaultConfig
        XCTAssertEqual(cfg.mode, .validate)
        XCTAssertFalse(cfg.rules.isEmpty)
        XCTAssertTrue(cfg.rules.allSatisfy { $0.builtin })
        XCTAssertTrue(cfg.rules.allSatisfy { $0.enabled })
    }

    func test_pendingCommand_codableRoundTrip() throws {
        let original = PendingCommand(
            id: "abc-123",
            source: "Claude Code",
            command: "DROP TABLE x",
            reason: "rule matched"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PendingCommand.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_logEntry_codableRoundTrip() throws {
        let now = Date()
        let original = LogEntry(
            id: "log-1",
            timestamp: now,
            command: "rm -rf /",
            source: "Test",
            cwd: "/tmp",
            ruleName: "rm -rf",
            rulePattern: "\\brm\\s+-rf",
            decision: .denied,
            resolvedAt: now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LogEntry.self, from: data)
        // Дата в ISO8601 теряет миллисекунды — сравниваем поля без timestamp.
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.command, original.command)
        XCTAssertEqual(decoded.decision, original.decision)
    }

    func test_logDecision_allCasesHaveLabelKey() {
        for d in LogDecision.allCases {
            XCTAssertFalse(d.labelKey.isEmpty)
        }
    }
}
