// SPDX-License-Identifier: MPL-2.0
import Foundation
import ProducerUpToDateCore
import OfficialUpdateSupport
import UpdateEnginePrototypeSupport

@main struct OfficialUpdateProbe {
    static func main() async {
        do {
            let args = Set(CommandLine.arguments.dropFirst())
            guard args.isSubset(of: ["--scan", "--check-online", "--validate-sources"]),
                  args.contains("--scan") != args.contains("--validate-sources") else {
                print("Use --scan [--check-online], or --validate-sources --check-online. Output is aggregate only."); return
            }
            let directory = try OfficialSourceDirectory.bundled()
            if args.contains("--validate-sources") {
                guard args.contains("--check-online") else { throw OfficialCheckError.permission }
                for entry in directory.entries {
                    let data = try PublicFeedTransport.fetch(entry.source, allowNetwork: true, html: true)
                    let version = try OfficialReleaseParser.version(data, entry: entry)
                    print("\(entry.id): official release \(version) · \(entry.source) · \(Date().ISO8601Format())")
                }
                return
            }
            let scan = try await ScanPipeline.run(configuration: .standard, scanDAWs: true)
            let targets = OfficialTarget.discover(products: scan.products, daws: scan.daws, directory: directory)
            print("Scope: standard locations; incomplete plugin locations \(scan.report.inaccessibleLocationCount); DAW warnings \(scan.dawWarnings.count); DAW scope notes \(scan.dawScopeNotes.count).")
            for kind in ["plugin:", "daw:"] {
                let copies = targets.filter { $0.productID.hasPrefix(kind) }
                let eligible = copies.filter { $0.entry != nil }
                print("\(kind) products \(Set(copies.map(\.productID)).count); copies \(copies.count); eligible products \(Set(eligible.map(\.productID)).count); eligible copies \(eligible.count).")
            }
            guard args.contains("--check-online") else { print("Offline only."); return }
            let observations = try OfficialCheckRunner.check(targets, allowNetwork: true)
            let now = Date()
            for state in [OfficialResultState.update, .matched, .ahead, .ambiguous, .failed, .stale] {
                print("\(state.rawValue): \(observations.filter { $0.state(at: now) == state }.count) copies.")
            }
            let comparedIDs = Set(observations.filter { [.update, .matched, .ahead].contains($0.state(at: now)) }.map(\.copyID))
            let groups = Dictionary(grouping: targets, by: \.productID)
            print("Products with every copy compared: \(groups.values.filter { $0.allSatisfy { comparedIDs.contains($0.id) } }.count).")
        } catch { print("Check failed: \(error.localizedDescription)"); exit(1) }
    }
}
