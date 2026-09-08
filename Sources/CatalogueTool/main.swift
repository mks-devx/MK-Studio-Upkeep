// SPDX-License-Identifier: BUSL-1.1
import CryptoKit
import Foundation
import ProducerUpToDateCore
import MaintainerCatalogueSupport

// Writes a deployable static directory locally. Does not sign, upload or configure hosting.
let args = CommandLine.arguments
if args == [args[0], "--inspect-local-daws"] {
    do {
        let result = try DAWScanner().scanReport()
        for daw in result.records {
            let route = DAWUpdateSource.appStoreDestination(for: daw) != nil ? "App Store receipt → App Store Updates handoff"
                : DAWUpdateSource.checker(for: daw)?.name ?? "vendor/manager handoff"
            print("\(daw.name): \(daw.identityIsInferred ? "name-inferred" : "recognised bundle ID"); \(route)")
        }
        print("\(result.records.count) DAWs; \(result.warnings.count) scan warnings; \(result.scopeNotes.count) search-scope notes. Local inspection only; no inventory uploaded.")
        exit(0)
    } catch { fputs("DAW inspection failed.\n", stderr); exit(1) }
}
if args == [args[0], "--inspect-hardware"] {
    do {
        let report = try HardwareScanner.scan()
        print("Audio devices:")
        for device in report.devices {
            print("  \(device.name) · \(device.manufacturer) · \(device.transport) → \(device.guide.map { "updates via \($0.updateRoute)" } ?? "no reviewed update route")")
        }
        print("MIDI devices:")
        for device in report.midiDevices {
            print("  \(device.name) · \(device.manufacturer) · \(device.offline.map { $0 ? "offline" : "online" } ?? "status unknown") → \(device.guide.map { "updates via \($0.updateRoute)" } ?? "no reviewed update route")")
        }
        print("Drivers:")
        for driver in report.drivers {
            print("  \(driver.name) \(driver.version ?? "?") [\(driver.kind)]\n    \(DriverDescription.describe(driver))")
        }
        print("\(report.warnings.count) warnings. Local read-only inspection; nothing uploaded.")
        exit(0)
    } catch { fputs("Hardware inspection failed.\n", stderr); exit(1) }
}
if args == [args[0], "--check-vendors"] {
    var failed = false
    for vendor in DirectVendor.allCases where !vendor.isActive {
        print("\(vendor.name): not requested. \(vendor.inactiveReason ?? "")")
    }
    var previous: DirectVendor?
    for vendor in DirectVendor.active {
        do {
            let delay = DirectVendorChecks.politenessDelay(before: vendor, after: previous)
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            previous = vendor
            let observation = try await DirectVendorChecks.fetch(vendor)
            if vendor.dawDefinitionID != nil {
                let release = try DirectVendorChecks.dawRelease(from: observation)
                print("\(vendor.name): official version \(release.latestVersion) validated. No inventory sent or cache written.")
                continue
            }
            let records = try DirectVendorChecks.records(from: observation, baseline: [])
            print("\(vendor.name): \(records.count) official release observations validated. No inventory sent or cache written.")
        } catch { print("\(vendor.name): \(error.localizedDescription)"); failed = true }
    }
    exit(failed ? 1 : 0)
}
// Offline prototype: feed bodies are supplied by the caller, never fetched here.
if args.count == 5 && args[1] == "--prototype-updates" {
    do {
        func bounded(_ path: String) throws -> Data {
            let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
            guard data.count <= GeneralUpdateEngine.maximumBytes else { throw GeneralUpdateEngine.Failure.invalidFeed }
            return data
        }
        let registry = try JSONDecoder().decode(GeneralUpdateEngine.Registry.self, from: bounded(args[2]))
        let inventory = try JSONDecoder().decode([GeneralUpdateEngine.Installation].self, from: bounded(args[3]))
        let feeds = try JSONDecoder().decode([String: String].self, from: bounded(args[4]))
        let results = try await GeneralUpdateEngine.check(inventory, registry: registry) { url in
            guard let body = feeds[url.absoluteString] else { throw GeneralUpdateEngine.Failure.invalidFeed }
            return Data(body.utf8)
        }
        for (index, result) in results.enumerated() { print("Item \(index + 1): \(result.status)") }
        print("Offline fixture run: \(results.count) results. No vendor requests or inventory upload.")
        exit(0)
    } catch { fputs("Prototype input or evaluation failed.\n", stderr); exit(1) }
}
if args.count == 2 && args[1] == "--check-local-inventory" {
    do {
        let report = try PluginScanner().scan()
        let products = ProductNormalizer().normalize(records: report.records).products
        let results = products.map { PluginUpdateEvaluator.evaluate($0, catalogue: []) }
        print("Local standard-folder scan: \(report.records.count) files, \(products.count) products. No release comparison was performed; no inventory was uploaded.")
        let reasons = Dictionary(grouping: results.filter { $0.reason != nil }, by: { $0.reason! })
        for reason in reasons.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            print("\(reason.rawValue): \(reasons[reason]!.count)")
        }
        exit(0)
    } catch { fputs("Local scan failed.\n", stderr); exit(1) }
}
if args.count != 4 {
    fputs("Usage: CatalogueTool SIGNED_CATALOGUE PUBLIC_KEY.txt NEW_OUTPUT_DIRECTORY\nNo release catalogue or trust key is bundled. Supply an explicitly trusted base64 Ed25519 public key.\n", stderr)
    exit(2)
}
do {
    let input = URL(fileURLWithPath: args[1])
    let keyURL = URL(fileURLWithPath: args[2])
    let output = URL(fileURLWithPath: args[3])
    guard !FileManager.default.fileExists(atPath: output.path) else { throw CocoaError(.fileWriteFileExists) }
    guard let data = SafeFileAccess.data(at: input, maximumBytes: CatalogueValidator.maximumBytes),
          let keyData = SafeFileAccess.data(at: keyURL, maximumBytes: 256),
          let keyText = String(data: keyData, encoding: .utf8),
          let publicKey = Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)),
          publicKey.count == 32 else { throw CatalogueError.invalidData }
    let snapshot = try CatalogueValidator.verify(data, publicKey: publicKey)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try data.write(to: output.appendingPathComponent("catalogue.signed.json"), options: .withoutOverwriting)
    let metadata: [String: Any] = ["sequence": snapshot.sequence, "generatedOn": snapshot.generatedOn,
        "sha256": digest, "plugins": snapshot.plugins.count, "schemaVersion": snapshot.schemaVersion]
    try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        .write(to: output.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
    try "/*\n  Content-Type: application/json\n  Cache-Control: public, max-age=300, must-revalidate\n  X-Content-Type-Options: nosniff\n".write(to: output.appendingPathComponent("_headers"), atomically: false, encoding: .utf8)
    print("Verified feed package: sequence \(snapshot.sequence), \(snapshot.plugins.count) products. Local files only; nothing published.")
} catch {
    fputs("Feed preparation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
