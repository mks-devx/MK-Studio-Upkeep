// SPDX-License-Identifier: BUSL-1.1
import Foundation
import ProducerUpToDateCore
import UpdateEnginePrototypeSupport

@main struct UpdateEnginePrototype {
    static func main() async {
        do { try await run() }
        catch { print("Prototype could not finish: \(error.localizedDescription)"); exit(1) }
    }
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args == ["--help"] {
            print("""
            Update engine diagnostic prototype (not the app's update service)
            --scan                         Read standard plugin/DAW locations; aggregate coverage only.
            --scan --check-online          Also fetch up to 32 eligible declared feeds, by explicit opt-in.
            --feed HTTPS_URL --installed-build BUILD --check-online
                                           Test one explicitly supplied feed against a build number.
            --details                      Include local product/copy names and source URLs in the output.
            Online mode contacts DNS and feed hosts; those services receive connection information.
            It sends no inventory body, version parameters or paths. No installer is downloaded or run.
            """)
            return
        }
        let options = Set(["--scan", "--check-online", "--details", "--feed", "--installed-build"])
        var flags: Set<String> = [], values: [String: String] = [:], i = 0
        while i < args.count {
            let key = args[i]
            guard options.contains(key), !flags.contains(key), values[key] == nil else { throw FeedFailure.unsupported }
            if key == "--feed" || key == "--installed-build" {
                i += 1; guard i < args.count else { throw FeedFailure.unsupported }; values[key] = args[i]
            } else { flags.insert(key) }
            i += 1
        }
        let plan: FeedCoveragePlan
        if flags.contains("--scan") {
            guard values.isEmpty else { throw FeedFailure.unsupported }
            let scan = try await ScanPipeline.run(configuration: .standard, scanDAWs: true)
            plan = FeedCoveragePlan(targets: FeedTarget.discover(in: scan))
            print("Scan scope: standard plugin and application locations; custom folders excluded.")
            print("Plugin locations incomplete: \(scan.report.inaccessibleLocationCount); DAW scan warnings: \(scan.dawWarnings.count); scope notes: \(scan.dawScopeNotes.count).")
        } else {
            guard let raw = values["--feed"], let url = URL(string: raw), PublicFeedTransport.acceptedURL(url),
                  let build = values["--installed-build"], flags.contains("--check-online") else { throw FeedFailure.unsupported }
            plan = FeedCoveragePlan(targets: [.init(productID: "explicit-feed-test", name: "Explicit feed test", copy: "Supplied build", build: build, source: url)])
        }
        print("Products: \(plan.productCount); installed copies: \(plan.targets.count).")
        print("Products with a supported declared address: \(plan.declaredProductCount); eligible for a feed check: \(plan.eligibleProductCount).")
        let groups = Dictionary(grouping: plan.targets.filter { $0.unavailableReason != nil }, by: { $0.unavailableReason! })
        for key in groups.keys.sorted() { print("\(key): \(groups[key]!.count) copies") }
        if flags.contains("--details") {
            for target in plan.targets {
                print("\(target.name) | \(target.copy) | \(target.source?.absoluteString ?? "No feed") | \(target.unavailableReason ?? "Eligible")")
            }
        }
        guard flags.contains("--check-online") else { print("Offline discovery complete. No DNS or HTTP update checks were requested."); return }
        print("Online checks enabled for this run. Downloading release metadata only.")
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let worker = Task.detached(priority: .utility) {
            try FeedCheckRunner.check(plan, allowNetwork: true, macOS: osVersion, appleSilicon: MacArchitecture.current.processor == .appleSilicon)
        }
        let observations = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        let checked = observations.filter { $0.result != nil }
        print("Compared copies: \(checked.count); products with at least one compared copy: \(Set(checked.map { $0.target.productID }).count).")
        print("Copies with updates: \(checked.filter { $0.result?.update != nil }.count); copies with a feed-marked major upgrade: \(checked.filter { $0.result?.newerEdition != nil }.count).")
        print("Copies with no compatible update found: \(checked.filter { $0.result?.noUpdateFound == true }.count).")
        let failures = Dictionary(grouping: observations.filter { $0.failure != nil }, by: { $0.failure! })
        for key in failures.keys.sorted() { print("Could not check: \(key) (\(failures[key]!.count) copies)") }
        if flags.contains("--details") {
            for observation in checked {
                guard let result = observation.result else { continue }
                print("\(observation.target.name) | \(observation.target.copy) | installed build \(observation.target.build ?? "Unknown") | update \(result.update?.version ?? "None") | major upgrade \(result.newerEdition?.version ?? "None") | \(result.source.absoluteString) | \(result.checkedAt.ISO8601Format())")
            }
        }
        print("A feed-marked major upgrade may cost extra. Source time and results are retained only for this run.")
    }
}
