// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Bounds metadata reads and rejects links outside the inspected bundle.
public enum SafeFileAccess {
    public static func data(at url: URL, maximumBytes: Int = 4_194_304) -> Data? {
        guard url.isFileURL, maximumBytes >= 0, maximumBytes < Int.max else { return nil }
        // Inspect the opened descriptor: a file swapped for a FIFO or symlink between
        // a path check and open must never block or redirect a metadata read.
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else { close(descriptor); return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumBytes + 1),
              data.count <= maximumBytes else { return nil }
        return data
    }

    /// Read only a bounded header from an ordinary file, even if the file is large.
    public static func prefix(at url: URL, count: Int) -> Data? {
        guard url.isFileURL, count > 0, count <= 65_536 else { return nil }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        var bytes = [UInt8](repeating: 0, count: count)
        let length = read(descriptor, &bytes, count)
        guard length >= 0 else { return nil }
        return Data(bytes.prefix(length))
    }

    public static func contained(_ url: URL, in root: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix(base + "/")
    }

    public static func executable(in bundle: URL, name: String?) -> URL? {
        guard let name, !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\") else { return nil }
        let url = bundle.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
        guard contained(url, in: bundle),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return url
    }
}
