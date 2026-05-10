//
//  PendingStoreTests.swift
//  ApprovalCoreTests
//

import XCTest
@testable import ApprovalCore

@MainActor
final class PendingStoreTests: XCTestCase {
    private func makeCommand(id: String = UUID().uuidString) -> PendingCommand {
        PendingCommand(id: id, source: "test", command: "echo hi", reason: "rule X")
    }

    func test_add_appendsToPendingAndStoresCallback() {
        let store = PendingStore()
        let cmd = makeCommand()

        var resolved: Bool?
        store.add(cmd) { resolved = $0 }

        XCTAssertEqual(store.pending.count, 1)
        XCTAssertEqual(store.pending.first?.id, cmd.id)
        XCTAssertNil(resolved)
    }

    func test_resolve_returnsTrueAndFiresCallbackOnFirstCall() {
        let store = PendingStore()
        let cmd = makeCommand()

        var resolved: Bool?
        store.add(cmd) { resolved = $0 }

        let didResolve = store.resolve(id: cmd.id, approved: true)
        XCTAssertTrue(didResolve)
        XCTAssertEqual(resolved, true)
        XCTAssertTrue(store.pending.isEmpty)
    }

    func test_resolve_returnsFalseAndDoesNotFireOnSecondCall() {
        // Идемпотентность: timeout сработал после Approve — второй
        // вызов должен быть тихим no-op, без double-callback.
        let store = PendingStore()
        let cmd = makeCommand()

        var callbackCount = 0
        store.add(cmd) { _ in callbackCount += 1 }

        XCTAssertTrue(store.resolve(id: cmd.id, approved: true))
        XCTAssertFalse(store.resolve(id: cmd.id, approved: false))
        XCTAssertEqual(callbackCount, 1)
    }

    func test_resolve_returnsFalseForUnknownID() {
        let store = PendingStore()
        XCTAssertFalse(store.resolve(id: "ghost", approved: true))
    }

    func test_resolve_passesApprovedFlagToCallback() {
        let store = PendingStore()

        let cmd1 = makeCommand(id: "a")
        let cmd2 = makeCommand(id: "b")
        var got: [String: Bool] = [:]
        store.add(cmd1) { got["a"] = $0 }
        store.add(cmd2) { got["b"] = $0 }

        store.resolve(id: "a", approved: true)
        store.resolve(id: "b", approved: false)

        XCTAssertEqual(got["a"], true)
        XCTAssertEqual(got["b"], false)
    }

    func test_get_returnsCommandWhilePendingAndNilAfterResolve() {
        let store = PendingStore()
        let cmd = makeCommand(id: "x")
        store.add(cmd) { _ in }

        XCTAssertEqual(store.get(id: "x")?.id, "x")
        store.resolve(id: "x", approved: true)
        XCTAssertNil(store.get(id: "x"))
    }

    func test_pendingArray_keepsInsertionOrder() {
        let store = PendingStore()
        for id in ["first", "second", "third"] {
            store.add(makeCommand(id: id)) { _ in }
        }
        XCTAssertEqual(store.pending.map(\.id), ["first", "second", "third"])
    }
}
