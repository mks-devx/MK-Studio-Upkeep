// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import Foundation

/// Moves a reviewed item to the Trash. Items in root-owned folders (the Core Audio HAL and
/// MIDI Drivers folders) cannot be moved by the app itself, so Finder is asked to do it and
/// macOS shows its own administrator-password prompt. Nothing else is sent to Finder.
enum TrashMover {
    enum Failure: LocalizedError {
        case finderDeclined(String)
        var errorDescription: String? {
            switch self {
            case let .finderDeclined(detail): "Finder did not move the item. \(detail)"
            }
        }
    }

    static func moveToTrash(_ url: URL) throws {
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        } catch let error as NSError where isPermissionProblem(error) {
            try moveWithFinder(url)
        }
    }

    static func restoreFromBackup(_ source: URL, to destination: URL, backupRoot: URL) throws {
        let source = source.standardizedFileURL
        let destination = destination.standardizedFileURL
        guard source.path.hasPrefix(backupRoot.standardizedFileURL.path + "/"),
              source.lastPathComponent == destination.lastPathComponent,
              !FileManager.default.fileExists(atPath: destination.path) else {
            throw Failure.finderDeclined("The backup or original location changed. Nothing was replaced.")
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch let error as NSError where isPermissionProblem(error) {
            try restoreWithFinder(source, to: destination)
        }
    }

    static func isPermissionProblem(_ error: NSError) -> Bool {
        (error.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(error.code))
            || (error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code))
    }

    /// The only folders Finder is ever asked about: the system-level plug-in, driver and
    /// application locations, where installers leave root-owned bundles the app itself cannot
    /// move. Nothing under the user's home folder is ever escalated to an administrator prompt.
    static let finderAssistedRoots = ["/Library/Audio/Plug-Ins/", "/Library/Audio/MIDI Drivers/", "/Applications/"]

    /// Fixed script, one literal path, no shell. The path is passed as a quoted AppleScript
    /// string so it can never be interpreted as script text. Finder is addressed by bundle
    /// identifier rather than by name.
    static func finderScript(for url: URL) -> String {
        let escaped = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "tell application id \"com.apple.finder\" to delete (POSIX file \"\(escaped)\" as alias)"
    }

    static func finderRestoreScript(source: URL, destination: URL) -> String {
        let sourcePath = appleScriptLiteral(source.path)
        let parentPath = appleScriptLiteral(destination.deletingLastPathComponent().path)
        return "tell application id \"com.apple.finder\" to move (POSIX file \"\(sourcePath)\" as alias) to (POSIX file \"\(parentPath)\" as alias)"
    }

    private static func moveWithFinder(_ original: URL) throws {
        let url = original.standardizedFileURL
        guard finderAssistedRoots.contains(where: { url.path.hasPrefix($0) }) else {
            throw Failure.finderDeclined("This item is in one of your own folders but could not be moved. Check its permissions or drag it to the Trash in Finder.")
        }
        // Immediately before the request: the item must still be a real folder, not a link, so the
        // alias Finder resolves cannot point anywhere else.
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              url.resolvingSymlinksInPath().path == url.path else {
            throw Failure.finderDeclined("The item changed before it could be moved. Nothing was moved.")
        }
        var failure: String?
        let run = {
            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: finderScript(for: url)) else { failure = "The Finder request could not be prepared."; return }
            script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error."
                let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                failure = code == -128 ? "You cancelled the administrator prompt." : code == -1743
                    ? "macOS did not allow MK Studio Upkeep to control Finder. Allow it in System Settings › Privacy & Security › Automation, or move the selected software using Finder."
                    : message
            }
        }
        if Thread.isMainThread { run() } else { DispatchQueue.main.sync(execute: run) }
        if let failure { throw Failure.finderDeclined(failure) }
        // Finder reports success once the move is done; confirm the item is gone.
        if FileManager.default.fileExists(atPath: url.path) { throw Failure.finderDeclined("The item is still in place.") }
    }

    private static func restoreWithFinder(_ source: URL, to destination: URL) throws {
        guard finderAssistedRoots.contains(where: { destination.path.hasPrefix($0) }),
              !FileManager.default.fileExists(atPath: destination.path) else {
            throw Failure.finderDeclined("The original location is not an approved system software folder or is already occupied.")
        }
        var info = stat()
        guard lstat(source.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              source.resolvingSymlinksInPath().path == source.path else {
            throw Failure.finderDeclined("The verified backup changed before it could be restored.")
        }
        var failure: String?
        let run = {
            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: finderRestoreScript(source: source, destination: destination)) else {
                failure = "The Finder restore request could not be prepared."
                return
            }
            script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error."
                let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                failure = code == -128 ? "You cancelled the administrator prompt." : code == -1743
                    ? "macOS did not allow MK Studio Upkeep to control Finder. Allow it in System Settings › Privacy & Security › Automation, then try again."
                    : message
            }
        }
        if Thread.isMainThread { run() } else { DispatchQueue.main.sync(execute: run) }
        if let failure { throw Failure.finderDeclined(failure) }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw Failure.finderDeclined("The restored item did not appear at its original location.")
        }
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
