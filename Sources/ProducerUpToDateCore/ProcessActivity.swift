// SPDX-License-Identifier: MPL-2.0
import Darwin
import Foundation

/// On-demand, local process readings. No arguments, environment or executable paths are read.
public enum ProcessActivity {
    public struct Entry: Identifiable, Sendable, Equatable {
        public let id: Int
        public let name: String
        public let cpu: Double
        public let residentBytes: UInt64
    }
    public struct Snapshot: Sendable {
        public let cpu: [Entry]
        public let memory: [Entry]
    }
    public enum Ranking { case cpu, memory }
    public enum Failure: Error { case unavailable }

    public static func parse(_ text: String, excluding pid: Int = -1, ranking: Ranking = .cpu) -> [Entry] {
        text.split(separator: "\n").compactMap { line -> Entry? in
            let fields = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard fields.count == 4, let id = Int(fields[0]), id > 0, id != pid,
                  let cpu = Double(fields[1]), cpu.isFinite, cpu >= 0,
                  let kib = UInt64(fields[2]), kib <= UInt64.max / 1024,
                  let name = DisplaySanitiser.sanitise(String(fields[3]), maximumLength: 80) else { return nil }
            return Entry(id: id, name: name, cpu: cpu, residentBytes: kib * 1024)
        }.sorted {
            switch ranking {
            case .cpu: return $0.cpu == $1.cpu ? $0.id < $1.id : $0.cpu > $1.cpu
            case .memory: return $0.residentBytes == $1.residentBytes ? $0.id < $1.id : $0.residentBytes > $1.residentBytes
            }
        }.prefix(5).map { $0 }
    }

    /// ps reports a decaying CPU average over up to a minute, not a real-time audio measurement.
    public static func read() throws -> Snapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-o", "pid=,pcpu=,rss=,ucomm="]
        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let fd = pipe.fileHandleForReading.fileDescriptor
        defer {
            if process.isRunning { process.terminate() }
            try? pipe.fileHandleForReading.close()
        }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { throw Failure.unavailable }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while true {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.unavailable }
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count <= 1_048_576 else { throw Failure.unavailable }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 { break }
            else if errno == EAGAIN || errno == EINTR { usleep(10_000) }
            else { throw Failure.unavailable }
        }
        while process.isRunning {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.unavailable }
            usleep(10_000)
        }
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { throw Failure.unavailable }
        let entries = parse(text, excluding: Int(process.processIdentifier))
        guard !entries.isEmpty else { throw Failure.unavailable }
        return Snapshot(cpu: entries, memory: parse(text, excluding: Int(process.processIdentifier), ranking: .memory))
    }
}
