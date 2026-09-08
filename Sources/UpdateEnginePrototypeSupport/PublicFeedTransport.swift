// SPDX-License-Identifier: BUSL-1.1
import Darwin
import Foundation
import ProducerUpToDateCore

/// Shared bounded metadata transport. Resolves a public
/// IPv4 address and pins that address for HTTPS while retaining hostname TLS checks.
/// No shell, redirect, proxy, cookie store, credentials, or installer handling.
public enum PublicFeedTransport {
    public static func acceptedURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host,
              host.utf8.count <= 253, !host.hasSuffix("."),
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && $0.count <= 63 && $0.first != "-" && $0.last != "-"
              }),
              DeclaredProductLink(kind: .updateFeed, value: url.absoluteString) != nil else { return false }
        return !["localhost", "local", "internal", "home", "lan", "test", "invalid", "example", "onion"].contains(host.split(separator: ".").last.map(String.init) ?? "")
    }

    static func isPublicIPv4(_ raw: String) -> Bool {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let values = parts.compactMap { UInt8($0) }
        guard values.count == 4, zip(parts, values).allSatisfy({ String($0.1) == $0.0 }) else { return false }
        let a = Int(values[0]), b = Int(values[1]), c = Int(values[2])
        if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        if a == 169 && b == 254 || a == 172 && (16...31).contains(b) { return false }
        if a == 192 && (b == 0 || b == 168 || b == 88 && c == 99) { return false }
        if a == 198 && (b == 18 || b == 19 || b == 51 && c == 100) { return false }
        if a == 203 && b == 0 && c == 113 { return false }
        return true
    }

    static func arguments(url: URL, address: String, html: Bool = false) throws -> [String] {
        guard acceptedURL(url), let host = url.host, isPublicIPv4(address) else { throw FeedFailure.unsafeAddress }
        return ["-q", "--silent", "--globoff", "--ipv4", "--proto", "=https", "--proxy", "", "--noproxy", "*",
                "--resolve", "\(host):443:\(address)", "--connect-timeout", "5", "--max-time", "15",
                "--max-filesize", String(SparkleFeed.maximumBytes), "--header", "Accept-Encoding: identity",
                "--header", html ? "Accept: text/html" : "Accept: application/rss+xml, application/xml, text/xml",
                "--user-agent", "MK-Studio-Upkeep-Update-Check",
                "--write-out", "\n%{http_code}\n%{content_type}", "--url", url.absoluteString]
    }

    public static func fetch(_ url: URL, allowNetwork: Bool, html: Bool = false) throws -> Data {
        guard allowNetwork else { throw FeedFailure.network }
        guard acceptedURL(url), let host = url.host else { throw FeedFailure.unsafeAddress }
        let dns = try BoundedProcess.read(executable: "/usr/bin/dscacheutil", arguments: ["-q", "host", "-a", "name", host], maximumBytes: 65_536, timeout: 6)
        guard let text = String(data: dns, encoding: .utf8) else { throw FeedFailure.network }
        let addresses = text.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("ip_address:") else { return nil }
            return line.dropFirst("ip_address:".count).trimmingCharacters(in: .whitespaces)
        }
        guard !addresses.isEmpty, addresses.allSatisfy(isPublicIPv4), let address = addresses.first else { throw FeedFailure.unsafeAddress }
        let response = try BoundedProcess.read(executable: "/usr/bin/curl", arguments: arguments(url: url, address: address, html: html), maximumBytes: SparkleFeed.maximumBytes + 1024, timeout: 17)
        return try body(from: response, html: html)
    }

    static func body(from response: Data, html: Bool = false) throws -> Data {
        guard let typeBoundary = response.lastIndex(of: 10), typeBoundary >= 4,
              let statusBoundary = response[..<typeBoundary].lastIndex(of: 10),
              String(data: response[(statusBoundary + 1)..<typeBoundary], encoding: .utf8) == "200",
              let rawType = String(data: response[(typeBoundary + 1)...], encoding: .utf8) else { throw FeedFailure.network }
        let type = rawType.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        guard (html ? ["text/html"] : ["application/xml", "application/rss+xml", "text/xml", "text/plain"]).contains(type),
              statusBoundary <= SparkleFeed.maximumBytes else { throw FeedFailure.network }
        return Data(response[..<statusBoundary])
    }
}

enum BoundedProcess {
    static func read(executable: String, arguments: [String], maximumBytes: Int, timeout: Double) throws -> Data {
        try Task.checkCancellation()
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? pipe.fileHandleForReading.close()
        }
        let fd = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { throw FeedFailure.network }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw FeedFailure.network }
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count <= maximumBytes else { throw FeedFailure.network }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 { break }
            else if errno == EAGAIN || errno == EINTR { usleep(10_000) }
            else { throw FeedFailure.network }
        }
        while process.isRunning {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw FeedFailure.network }
            usleep(10_000)
        }
        guard process.terminationStatus == 0 else { throw FeedFailure.network }
        return data
    }
}
