//
//  ApprovalServer.swift
//  approval
//
//  Локальный IPC-сервер на Unix domain socket. Принимает по одному
//  newline-delimited JSON-запросу на соединение, отвечает таким же
//  JSON и закрывает соединение.
//

import Foundation
import Darwin
import Combine
import OSLog

nonisolated private let ipcLog = Logger(subsystem: "com.alexmasyukov.approval", category: "ipc")

/// Запрос от хука. Декодируется из JSON на background thread,
/// затем передаётся на MainActor. Явный `nonisolated` нужен в
/// проектах с default-MainActor-isolation, иначе Decodable
/// conformance и сами свойства считаются main-actor-isolated и
/// JSONDecoder из nonisolated context их не увидит.
nonisolated struct CheckRequest: Decodable, Sendable {
    let command: String
    let cwd: String?
    let source: String?
}

@MainActor
final class ApprovalServer: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String = ""

    private let rules: RulesStore
    private let pending: PendingStore
    private let log: LogStore
    private let coordinator: ApprovalCoordinator

    private var serverFd: Int32 = -1
    private var acceptThread: Thread?

    var socketPath: String { UnixSocket.socketPath }

    init(rules: RulesStore, pending: PendingStore, log: LogStore, coordinator: ApprovalCoordinator) {
        self.rules = rules
        self.pending = pending
        self.log = log
        self.coordinator = coordinator
    }

    // MARK: - Start / stop

    func start() {
        guard !isRunning else { return }

        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            lastError = "socket() failed: \(String(cString: strerror(errno)))"
            return
        }

        var (addr, addrLen) = UnixSocket.makeAddr(path: socketPath)
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            lastError = "bind() failed: \(String(cString: strerror(errno)))"
            close(fd)
            return
        }

        chmod(socketPath, 0o600)

        guard listen(fd, 32) == 0 else {
            lastError = "listen() failed: \(String(cString: strerror(errno)))"
            close(fd)
            unlink(socketPath)
            return
        }

        serverFd = fd
        isRunning = true
        lastError = ""
        print("ApprovalServer listening on \(socketPath)")

        // Захват self и fd в замыкание accept-loop потока.
        let server = self
        let capturedFd = fd
        let thread = Thread {
            ApprovalServer.acceptLoop(server: server, serverFd: capturedFd)
        }
        thread.name = "approval-server-accept"
        thread.start()
        acceptThread = thread
    }

    func stop() {
        guard isRunning else { return }
        let fd = serverFd
        serverFd = -1
        isRunning = false
        close(fd) // accept() в фоне получит EBADF и выйдет из цикла
        unlink(socketPath)
    }

    // MARK: - Accept loop / per-connection handler (background)

    nonisolated private static func acceptLoop(server: ApprovalServer, serverFd: Int32) {
        while true {
            let clientFd = accept(serverFd, nil, nil)
            if clientFd < 0 {
                if errno == EBADF || errno == EINVAL {
                    break
                }
                continue
            }
            DispatchQueue.global(qos: .userInitiated).async {
                ApprovalServer.handleClient(server: server, fd: clientFd)
            }
        }
    }

    nonisolated private static func handleClient(server: ApprovalServer, fd: Int32) {
        guard let data = UnixSocket.readLine(fd: fd) else {
            close(fd)
            return
        }

        guard let req = try? JSONDecoder().decode(CheckRequest.self, from: data) else {
            sendResponse(fd: fd, approved: false, reason: "bad json")
            return
        }

        Task { @MainActor in
            server.processCheck(req: req, fd: fd)
        }
    }

    // MARK: - Main-actor request processing

    private func processCheck(req: CheckRequest, fd: Int32) {
        if rules.config.mode == .passThrough {
            Self.sendResponse(fd: fd, approved: true, reason: "pass-through mode")
            return
        }

        guard let matched = rules.evaluate(command: req.command) else {
            Self.sendResponse(fd: fd, approved: true, reason: "no rule matched")
            return
        }

        let id = UUID().uuidString
        let detailReason = """
        Совпадение с правилом: \(matched.name)
        Паттерн: \(matched.pattern)

        Рабочая директория: \(req.cwd ?? "—")
        """
        let cmd = PendingCommand(
            id: id,
            source: req.source ?? IPCProtocol.defaultSource,
            command: req.command,
            reason: detailReason
        )

        log.append(LogEntry(
            id: id,
            timestamp: Date(),
            command: req.command,
            source: req.source ?? IPCProtocol.defaultSource,
            cwd: req.cwd,
            ruleName: matched.name,
            rulePattern: matched.pattern,
            decision: .pending,
            resolvedAt: nil
        ))

        let serverTimeout = TimeInterval(IPCProtocol.hookTimeoutSeconds + 60)
        let pendingRef = pending
        let timeoutWork = DispatchWorkItem {
            pendingRef.resolve(id: id, approved: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + serverTimeout, execute: timeoutWork)

        pending.add(cmd) { approved in
            timeoutWork.cancel()
            Self.sendResponse(
                fd: fd,
                approved: approved,
                reason: approved ? "user approved" : "user denied"
            )
        }

        coordinator.requestApproval(for: cmd)
    }

    // MARK: -

    nonisolated private static func sendResponse(fd: Int32, approved: Bool, reason: String) {
        let payload: [String: Any] = ["approved": approved, "reason": reason]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            ipcLog.error("sendResponse: failed to encode payload (approved=\(approved, privacy: .public))")
            close(fd)
            return
        }
        let ok = UnixSocket.writeLine(fd: fd, data: data)
        if !ok {
            // Чаще всего: хук-клиент уже закрыл свой конец (timeout, kill -9,
            // broken pipe). Ошибка не фатальна — без ответа хук пойдёт по
            // fail-open пути, — но без лога мы её просто не видим.
            let err = String(cString: strerror(errno))
            ipcLog.warning("sendResponse: writeLine failed (errno=\(errno, privacy: .public) \(err, privacy: .public))")
        }
        close(fd)
    }
}
