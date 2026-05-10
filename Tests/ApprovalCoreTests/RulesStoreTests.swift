import XCTest
@testable import ApprovalCore

@MainActor
final class RulesStoreTests: XCTestCase {

    private func makeTempStore(_ initialConfig: RulesConfig? = nil) throws -> (RulesStore, URL) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("approval-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("rules.json")

        if let cfg = initialConfig {
            let encoder = JSONEncoder()
            let data = try encoder.encode(cfg)
            try data.write(to: url)
        }

        let store = RulesStore(fileURL: url)
        return (store, url)
    }

    // MARK: - evaluate (validate mode)

    func test_evaluate_dropTableMatches() throws {
        let (store, _) = try makeTempStore()
        XCTAssertNotNil(store.evaluate(command: "DROP TABLE users;"))
        XCTAssertEqual(store.evaluate(command: "DROP TABLE users;")?.name, "DROP TABLE/DATABASE/SCHEMA")
    }

    func test_evaluate_caseInsensitive() throws {
        let (store, _) = try makeTempStore()
        XCTAssertNotNil(store.evaluate(command: "drop table users"))
        XCTAssertNotNil(store.evaluate(command: "Drop TaBlE x"))
    }

    func test_evaluate_safeCommand_returnsNil() throws {
        let (store, _) = try makeTempStore()
        XCTAssertNil(store.evaluate(command: "SELECT * FROM users"))
        XCTAssertNil(store.evaluate(command: "ls -la"))
        XCTAssertNil(store.evaluate(command: "git status"))
    }

    func test_evaluate_truncate() throws {
        let (store, _) = try makeTempStore()
        XCTAssertNotNil(store.evaluate(command: "TRUNCATE TABLE logs"))
        XCTAssertNotNil(store.evaluate(command: "TRUNCATE logs"))
    }

    func test_evaluate_rmRf_fullForm() throws {
        let (store, _) = try makeTempStore()
        XCTAssertNotNil(store.evaluate(command: "rm -rf /tmp/x"))
        XCTAssertNotNil(store.evaluate(command: "rm -fr /tmp/x"))
    }

    func test_evaluate_rmWithoutRf_doesNotMatch() throws {
        let (store, _) = try makeTempStore()
        XCTAssertNil(store.evaluate(command: "rm /tmp/file"))
        XCTAssertNil(store.evaluate(command: "rm -i /tmp/x"))
    }

    func test_evaluate_passThroughMode_alwaysReturnsNil() throws {
        let (store, _) = try makeTempStore()
        store.setMode(.passThrough)
        XCTAssertNil(store.evaluate(command: "DROP TABLE users;"))
        XCTAssertNil(store.evaluate(command: "rm -rf /"))
    }

    func test_evaluate_disabledRuleSkipped() throws {
        let (store, _) = try makeTempStore()
        // Отключаем правило "DROP TABLE/DATABASE/SCHEMA"
        if let rule = store.config.rules.first(where: { $0.name == "DROP TABLE/DATABASE/SCHEMA" }) {
            store.toggleRule(id: rule.id)
        }
        XCTAssertNil(store.evaluate(command: "DROP TABLE users"))
        // Но другие правила всё ещё работают
        XCTAssertNotNil(store.evaluate(command: "rm -rf /tmp/x"))
    }

    // MARK: - persistence

    // Все persistence-тесты ниже после мутации делают `flushSync()`,
    // потому что мутации (addRule, toggleRule, setMode и т.д.)
    // используют debounced async save — без явного flush файл может
    // ещё не быть записан к моменту перезагрузки во второй стор.

    func test_addRule_persistsToFile() throws {
        let (store, url) = try makeTempStore()
        let initial = store.config.rules.count
        store.addRule(Rule(name: "Custom", pattern: "WIBBLE\\s+WOBBLE", enabled: true))
        XCTAssertEqual(store.config.rules.count, initial + 1)
        store.flushSync()

        // Перезагружаем стор с того же файла — правило должно быть на месте.
        let store2 = RulesStore(fileURL: url)
        XCTAssertTrue(store2.config.rules.contains { $0.name == "Custom" })
    }

    func test_removeRule_persistsToFile() throws {
        let (store, url) = try makeTempStore()
        let rule = Rule(name: "ToRemove", pattern: "x", enabled: true)
        store.addRule(rule)
        store.removeRule(id: rule.id)
        store.flushSync()

        let store2 = RulesStore(fileURL: url)
        XCTAssertFalse(store2.config.rules.contains { $0.id == rule.id })
    }

    func test_toggleRule_persistsState() throws {
        let (store, url) = try makeTempStore()
        guard let id = store.config.rules.first?.id else {
            XCTFail("default config should have rules"); return
        }
        store.toggleRule(id: id)
        store.flushSync()

        let store2 = RulesStore(fileURL: url)
        let reloaded = store2.config.rules.first { $0.id == id }
        XCTAssertEqual(reloaded?.enabled, false)
    }

    func test_setMode_persists() throws {
        let (store, url) = try makeTempStore()
        store.setMode(.passThrough)
        store.flushSync()

        let store2 = RulesStore(fileURL: url)
        XCTAssertEqual(store2.config.mode, .passThrough)
    }

    func test_loadFromExistingFile() throws {
        let custom = RulesConfig(
            mode: .passThrough,
            rules: [Rule(name: "Only", pattern: "test", enabled: true)]
        )
        let (store, _) = try makeTempStore(custom)
        XCTAssertEqual(store.config.mode, .passThrough)
        XCTAssertEqual(store.config.rules.count, 1)
        XCTAssertEqual(store.config.rules.first?.name, "Only")
    }

    func test_freshFile_initializedWithDefaultConfig() throws {
        let (store, _) = try makeTempStore()
        XCTAssertEqual(store.config.mode, .validate)
        XCTAssertFalse(store.config.rules.isEmpty)
    }

    // MARK: - Robustness

    func test_evaluate_badRegexInRuleSkipped_otherRulesStillWork() throws {
        let custom = RulesConfig(
            mode: .validate,
            rules: [
                Rule(name: "broken", pattern: "[", enabled: true),         // невалидный regex
                Rule(name: "good", pattern: "DROP\\s+TABLE", enabled: true)
            ]
        )
        let (store, _) = try makeTempStore(custom)
        // Невалидное правило не должно крашить evaluate; валидное должно срабатывать.
        XCTAssertEqual(store.evaluate(command: "DROP TABLE x")?.name, "good")
    }

    func test_corruptedRulesFile_fallsBackToDefaults() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("approval-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("rules.json")
        // Записываем мусор вместо валидного JSON.
        try "not json at all".write(to: url, atomically: true, encoding: .utf8)

        let store = RulesStore(fileURL: url)
        // Должно загрузиться как default + перезаписаться.
        XCTAssertEqual(store.config.mode, .validate)
        XCTAssertFalse(store.config.rules.isEmpty)
    }
}
