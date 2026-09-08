// SPDX-License-Identifier: BUSL-1.1
import Combine
import Foundation
import ProducerUpToDateCore
import UpdateEnginePrototypeSupport

/// One session shared by Overview and details. Consent is deliberately not restored.
@MainActor public final class OfficialUpdateSession: ObservableObject {
    @Published public var optedIn = false {
        didSet { if !optedIn { invalidateResults() } }
    }
    @Published public private(set) var targets: [OfficialTarget] = []
    @Published public private(set) var observations: [OfficialObservation] = []
    @Published public private(set) var isChecking = false
    @Published public private(set) var message: String?
    @Published public private(set) var nextCheckAt = Date.distantPast
    @Published public private(set) var directory: OfficialSourceDirectory?
    private var targetsByProduct: [String: [OfficialTarget]] = [:]
    private var generation = UUID()
    private var task: Task<Void, Never>?
    public init() {
        do { directory = try OfficialSourceDirectory.bundled() }
        catch { message = OfficialCheckError.directory.rawValue }
    }
    public func reset(products: [NormalizedPluginProduct] = [], daws: [InstalledDAWRecord] = []) {
        invalidateResults()
        guard let directory else { targets = []; return }
        targets = OfficialTarget.discover(products: products, daws: daws, directory: directory)
        targetsByProduct = Dictionary(grouping: targets, by: \.productID)
    }
    public func invalidateResults() {
        generation = UUID(); task?.cancel(); task = nil
        isChecking = false; observations = []
        message = directory == nil ? OfficialCheckError.directory.rawValue : nil
    }
    public func rowLabel(productID: String, now: Date) -> String? {
        let copies = targetsByProduct[productID] ?? []
        guard copies.contains(where: { $0.entry != nil }) else { return nil }
        if isChecking { return "Checking…" }
        let ids = Set(copies.map(\.id))
        return OfficialProductSummary.label(total: copies.count, results: observations.filter { ids.contains($0.copyID) }, now: now)
    }
    public var eligibleCount: Int { targets.filter { $0.entry != nil }.count }
    public var productCount: Int { Set(targets.map(\.productID)).count }
    public var eligibleProductCount: Int { Set(targets.filter { $0.entry != nil }.map(\.productID)).count }
    public var hosts: String {
        Set(targets.compactMap { $0.entry?.source.host }).sorted().joined(separator: ", ")
    }
    public func check(fetch: @escaping @Sendable (URL) throws -> Data = { try PublicFeedTransport.fetch($0, allowNetwork: true, html: true) }) {
        guard optedIn, !isChecking, eligibleCount > 0, Date() >= nextCheckAt else { return }
        let current = UUID(); generation = current
        let inputs = targets
        isChecking = true; observations = []; message = nil
        nextCheckAt = Date().addingTimeInterval(60)
        task = Task {
            let worker = Task.detached(priority: .utility) { try OfficialCheckRunner.check(inputs, allowNetwork: true, fetch: fetch) }
            do {
                let results = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, generation == current, optedIn else { return }
                observations = results; isChecking = false
            } catch {
                guard generation == current else { return }
                isChecking = false; message = error is CancellationError ? "Check cancelled." : "The check could not finish. Try again."
            }
        }
    }
}
