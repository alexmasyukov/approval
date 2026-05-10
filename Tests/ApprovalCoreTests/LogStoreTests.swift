import XCTest
@testable import ApprovalCore

@MainActor
final class LogStoreTests: XCTestCase {

    private func makeTempStore() throws -> (LogStore, URL) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("approval-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("log.json")
        let store = LogStore(fileURL: url)
        return (store, url)
    }

    private func makeEntry(id: String = UUID().uuidString,
                            decision: LogDecision = .pending) -> LogEntry {
        LogEntry(
            id: id,
            timestamp: Date(),
            command: "echo \(id)",
            source: "test",
            cwd: nil,
            ruleName: "test rule",
            rulePattern: "echo",
            decision: decision,
            resolvedAt: nil
        )
    }

    func test_append_addsToFront() throws {
        let (store, _) = try makeTempStore()
        let a = makeEntry(id: "a")
        let b = makeEntry(id: "b")
        store.append(a)
        store.append(b)
        XCTAssertEqual(store.entries.first?.id, "b")
        XCTAssertEqual(store.entries.last?.id, "a")
    }

    func test_append_capsAt100Entries() throws {
        let (store, _) = try makeTempStore()
        for i in 0..<150 {
            store.append(makeEntry(id: "e-\(i)"))
        }
        XCTAssertEqual(store.entries.count, 100)
        // Newest stays — id "e-149"
        XCTAssertEqual(store.entries.first?.id, "e-149")
        // Oldest dropped — should NOT contain "e-49"
        XCTAssertFalse(store.entries.contains { $0.id == "e-49" })
        // 50 first surviving entries should be e-149..e-50
        XCTAssertEqual(store.entries.last?.id, "e-50")
    }

    func test_updateDecision_changesEntryAndSetsResolvedAt() throws {
        let (store, _) = try makeTempStore()
        let entry = makeEntry(id: "x", decision: .pending)
        store.append(entry)
        XCTAssertNil(store.entries.first?.resolvedAt)

        store.updateDecision(id: "x", decision: .approved)
        let updated = store.entries.first
        XCTAssertEqual(updated?.decision, .approved)
        XCTAssertNotNil(updated?.resolvedAt)
    }

    func test_updateDecision_unknownId_noOp() throws {
        let (store, _) = try makeTempStore()
        store.append(makeEntry(id: "real"))
        store.updateDecision(id: "ghost", decision: .denied)
        XCTAssertEqual(store.entries.first?.decision, .pending)
    }

    func test_clear_emptiesEntries() throws {
        let (store, _) = try makeTempStore()
        store.append(makeEntry())
        store.append(makeEntry())
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func test_clear_persistsImmediately() throws {
        let (store, url) = try makeTempStore()
        store.append(makeEntry())
        store.clear()
        // clear() пишет синхронно через flushSync — файл сразу должен быть пустым массивом.
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([LogEntry].self, from: data)
        XCTAssertTrue(loaded.isEmpty)
    }

    func test_flushSync_writesImmediatelyAndCanBeReread() throws {
        let (store, url) = try makeTempStore()
        store.append(makeEntry(id: "sync-test"))
        store.flushSync()

        let store2 = LogStore(fileURL: url)
        XCTAssertEqual(store2.entries.first?.id, "sync-test")
    }

    func test_loadFromExistingFile() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("approval-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("log.json")

        let initialEntries = [makeEntry(id: "saved-1"), makeEntry(id: "saved-2")]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(initialEntries).write(to: url)

        let store = LogStore(fileURL: url)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.map(\.id), ["saved-1", "saved-2"])
    }
}
