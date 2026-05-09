//
//  HookHandler.swift
//  approval
//
//  Логика PreToolUse-хука для Claude Code, встроенная прямо в бинарник.
//  Активируется аргументом `--hook` (см. main.swift).
//

import Foundation

enum HookHandler {
    private static let defaultPort: Int = 47823
    private static let timeoutSeconds: TimeInterval = 600

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
            exit(0) // невалидный JSON — пропустить
        }

        guard input.tool_name == "Bash" else {
            exit(0) // только Bash интересует
        }

        let command = input.tool_input?.command ?? ""
        guard !command.isEmpty else {
            exit(0)
        }

        let port = readPort()
        let url = URL(string: "http://localhost:\(port)/check")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeoutSeconds

        let payload: [String: String] = [
            "command": command,
            "cwd": input.cwd ?? "",
            "source": "Claude Code"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let semaphore = DispatchSemaphore(value: 0)
        var approved = true
        var reason = ""
        var transportError: Error?

        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: req) { data, _, error in
            defer { semaphore.signal() }
            if let error = error {
                transportError = error
                return
            }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                approved = json["approved"] as? Bool ?? true
                reason = json["reason"] as? String ?? ""
            }
        }
        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds + 5)
        if waitResult == .timedOut {
            task.cancel()
            writeStderr("approval hook: timeout, allowing")
            exit(0)
        }

        if let err = transportError {
            // Сервер недоступен (приложение не запущено) — fail-open с warning'ом.
            writeStderr("approval hook: server unreachable (\(err.localizedDescription)); allowing")
            exit(0)
        }

        if approved {
            exit(0)
        } else {
            writeStderr("Команда отклонена через approval app: \(reason)")
            exit(2)
        }
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

    private static func readPort() -> Int {
        let path = ("~/Library/Application Support/approval/port" as NSString).expandingTildeInPath
        if let content = try? String(contentsOfFile: path, encoding: .utf8),
           let value = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return value
        }
        return defaultPort
    }

    private static func writeStderr(_ message: String) {
        let line = message + "\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
