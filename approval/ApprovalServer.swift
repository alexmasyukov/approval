//
//  ApprovalServer.swift
//  approval
//

import Foundation
import Network
import Combine

@MainActor
final class ApprovalServer: ObservableObject {
    static let shared = ApprovalServer()

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String = ""
    let port: UInt16 = 47823

    private var listener: NWListener?

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in
                    self?.handle(connection: conn)
                }
            }
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.lastError = ""
                        print("ApprovalServer listening on \(self?.port ?? 0)")
                    case .failed(let err):
                        self?.isRunning = false
                        self?.lastError = "Server failed: \(err.localizedDescription)"
                        print("ApprovalServer failed: \(err)")
                    case .cancelled:
                        self?.isRunning = false
                    default: break
                    }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            lastError = "Failed to start: \(error.localizedDescription)"
            print("Failed to start ApprovalServer: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(connection conn: NWConnection) {
        conn.start(queue: .main)
        receive(on: conn, accumulated: Data())
    }

    private func receive(on conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            var buf = accumulated
            if let data = data { buf.append(data) }

            if let raw = String(data: buf, encoding: .utf8),
               let headerEndRange = raw.range(of: "\r\n\r\n") {
                let header = String(raw[..<headerEndRange.lowerBound])
                let bodyStr = String(raw[headerEndRange.upperBound...])
                var contentLength = 0
                for line in header.split(separator: "\r\n") {
                    let lower = line.lowercased()
                    if lower.hasPrefix("content-length:") {
                        let val = String(line).dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                        contentLength = Int(val) ?? 0
                    }
                }
                let bodyData = Data(bodyStr.utf8)
                if bodyData.count >= contentLength {
                    let body = bodyData.prefix(contentLength)
                    Task { @MainActor in
                        self.processRequest(header: header, body: Data(body), conn: conn)
                    }
                    return
                }
            }

            if isComplete || error != nil {
                conn.cancel()
                return
            }
            self.receive(on: conn, accumulated: buf)
        }
    }

    private func processRequest(header: String, body: Data, conn: NWConnection) {
        guard let firstLine = header.split(separator: "\r\n").first else {
            sendResponse(conn: conn, status: 400, body: "Bad Request")
            return
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(conn: conn, status: 400, body: "Bad Request")
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])

        switch (method, path) {
        case ("POST", "/check"):
            handleCheck(body: body, conn: conn)
        case ("GET", "/health"):
            sendResponse(conn: conn, status: 200, body: "{\"status\":\"ok\"}", contentType: "application/json")
        default:
            sendResponse(conn: conn, status: 404, body: "Not Found")
        }
    }

    struct CheckRequest: Codable {
        let command: String
        let cwd: String?
        let source: String?
    }

    private func handleCheck(body: Data, conn: NWConnection) {
        guard let req = try? JSONDecoder().decode(CheckRequest.self, from: body) else {
            sendResponse(conn: conn, status: 400, body: "{\"approved\":false,\"reason\":\"bad json\"}", contentType: "application/json")
            return
        }

        let store = RulesStore.shared

        if store.config.mode == .passThrough {
            sendResponse(conn: conn, status: 200,
                         body: "{\"approved\":true,\"reason\":\"pass-through mode\"}",
                         contentType: "application/json")
            return
        }

        guard let matched = store.evaluate(command: req.command) else {
            sendResponse(conn: conn, status: 200,
                         body: "{\"approved\":true,\"reason\":\"no rule matched\"}",
                         contentType: "application/json")
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
            source: req.source ?? "Claude Code",
            command: req.command,
            reason: detailReason
        )

        LogStore.shared.append(LogEntry(
            id: id,
            timestamp: Date(),
            command: req.command,
            source: req.source ?? "Claude Code",
            cwd: req.cwd,
            ruleName: matched.name,
            rulePattern: matched.pattern,
            decision: .pending,
            resolvedAt: nil
        ))

        PendingStore.shared.add(cmd) { [weak self] approved in
            let respJson = "{\"approved\":\(approved ? "true" : "false"),\"reason\":\"\(approved ? "user approved" : "user denied")\"}"
            self?.sendResponse(conn: conn, status: 200, body: respJson, contentType: "application/json")
        }

        ApprovalCoordinator.shared.requestApproval(for: cmd)
    }

    private func sendResponse(conn: NWConnection, status: Int, body: String, contentType: String = "text/plain") {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }
        let resp = "HTTP/1.1 \(status) \(statusText)\r\n" +
                   "Content-Type: \(contentType)\r\n" +
                   "Content-Length: \(body.utf8.count)\r\n" +
                   "Connection: close\r\n" +
                   "\r\n" +
                   body
        conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
