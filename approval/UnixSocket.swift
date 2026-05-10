//
//  UnixSocket.swift
//  approval
//
//  Маленькие POSIX-утилиты для Unix domain sockets, общие для
//  сервера и хук-клиента.
//

import Foundation
import Darwin

enum UnixSocket {
    static var socketPath: String { AppPaths.socketPath }

    /// Заполняет sockaddr_un по пути; возвращает корректный socklen_t.
    nonisolated static func makeAddr(path: String) -> (sockaddr_un, socklen_t) {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // sun_path — фиксированный массив CChar; копируем туда путь.
        // Размер берём из временного экземпляра, чтобы не было overlapping access.
        let cap = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let dest = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            path.withCString { src in
                _ = strlcpy(dest, src, cap)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        return (addr, len)
    }

    /// Читает из fd до символа `\n` или EOF/ошибки.
    nonisolated static func readLine(fd: Int32, maxBytes: Int = 1 << 20) -> Data? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count < maxBytes {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return buffer.isEmpty ? nil : buffer }
            buffer.append(chunk, count: n)
            if let last = buffer.last, last == 0x0A {
                return buffer
            }
        }
        return buffer
    }

    /// Пишет данные + `\n` в fd. Возвращает true если всё записалось.
    @discardableResult
    nonisolated static func writeLine(fd: Int32, data: Data) -> Bool {
        var payload = data
        if payload.last != 0x0A {
            payload.append(0x0A)
        }
        var written = 0
        return payload.withUnsafeBytes { rawBuf -> Bool in
            guard let base = rawBuf.baseAddress else { return false }
            while written < payload.count {
                let n = write(fd, base.advanced(by: written), payload.count - written)
                if n <= 0 { return false }
                written += n
            }
            return true
        }
    }
}
