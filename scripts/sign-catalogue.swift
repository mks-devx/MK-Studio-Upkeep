#!/usr/bin/env swift
// SPDX-License-Identifier: BUSL-1.1
import CryptoKit
import Foundation

// Offline editorial tool. Never put the private-key path or key in public artifacts.
let args = CommandLine.arguments
let generate = args.count == 6 && args[5] == "--generate"
if args.count != 5 && !generate {
    fputs("Usage: swift scripts/sign-catalogue.swift INPUT.json PRIVATE_KEY OUTPUT.signed.json PUBLIC_KEY.txt [--generate]\n", stderr)
    fputs("--generate creates a new private key at PRIVATE_KEY only when the file does not exist; a typo in the path never silently creates a key.\n", stderr)
    exit(2)
}
let keyURL = URL(fileURLWithPath: args[2])
let key: Curve25519.Signing.PrivateKey
if FileManager.default.fileExists(atPath: keyURL.path) {
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
} else if generate {
    key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    // Created with owner-only permissions inside a 0700 directory.
    guard FileManager.default.createFile(atPath: keyURL.path, contents: key.rawRepresentation, attributes: [.posixPermissions: 0o600]) else {
        fputs("Could not create the private key file.\n", stderr); exit(1)
    }
} else {
    fputs("Private key not found at \(keyURL.path). Check the path, or pass --generate to create a new key there.\n", stderr)
    exit(1)
}
let payload = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let envelope = ["payload": payload.base64EncodedString(), "signature": try key.signature(for: payload).base64EncodedString()]
let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
try data.write(to: URL(fileURLWithPath: args[3]), options: .atomic)
try (key.publicKey.rawRepresentation.base64EncodedString() + "\n").write(toFile: args[4], atomically: true, encoding: .utf8)
print("Signed catalogue written. Keep the private signing key offline and backed up.")
