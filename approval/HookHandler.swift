//
//  HookHandler.swift
//  approval
//
//  Логика PreToolUse-хука для Claude Code, встроенная в бинарник.
//  Активируется аргументом `--hook` (см. main.swift).
//

import Foundation
import Darwin

enum HookHandler {
    private static var timeoutSeconds: Int { IPCProtocol.hookTimeoutSeconds }

    static func run() -> Never {
        guard let stdinData = readStdin() else {
            exit(0) // нет ввода — пропустить
        }

        struct HookInput: Decodable {
            let tool_name: String?
            let cwd: String?
            let tool_input: ToolInput?
            struct ToolInput: Decodable { let command: String? }
        }

        guard let input = try? JSONDecoder().decode(HookInput.self, from: stdinData) else {
            exit(0)
        }
        guard input.tool_name == "Bash" else { exit(0) }

        let command = input.tool_input?.command ?? ""
        guard !command.isEmpty else { exit(0) }

        let payload: [String: String] = [
            "command": command,
            "cwd": input.cwd ?? "",
            "source": IPCProtocol.defaultSource
        ]
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            exit(0)
        }

        let result = roundTrip(request: payloadData)

        switch result {
        case .approved:
            exit(0)
        case .denied(let reason):
            writeStderr("Команда отклонена через approval app: \(reason)")
            exit(2)
        case .error(let message):
            writeStderr("approval hook: \(message); allowing")
            exit(0)
        }
    }

    // MARK: - Socket round-trip

    private enum HookResult {
        case approved
        case denied(reason: String)
        case error(message: String)
    }

    private static func roundTrip(request: Data) -> HookResult {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            return .error(message: "socket() failed: \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }

        // Read/write timeout — на случай если сервер завис.
        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var (addr, addrLen) = UnixSocket.makeAddr(path: UnixSocket.socketPath)
        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, addrLen)
            }
        }
        if connectResult != 0 {
            // Сервер не запущен — fail open
            return .error(message: "сервер недоступен (\(String(cString: strerror(errno))))")
        }

        guard UnixSocket.writeLine(fd: fd, data: request) else {
            return .error(message: "write failed")
        }

        guard let response = UnixSocket.readLine(fd: fd),
              let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            return .error(message: "не удалось прочитать ответ")
        }

        let approved = json["approved"] as? Bool ?? true
        let reason = json["reason"] as? String ?? ""
        return approved ? .approved : .denied(reason: reason)
    }

    // MARK: -

    private static func readStdin() -> Data? {
        let handle = FileHandle.standardInput
        var data = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data.isEmpty ? nil : data
    }

    private static func writeStderr(_ message: String) {
        let line = message + "\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
