// SPDX-License-Identifier: BUSL-1.1
import Foundation

public struct StudioScanResult: Sendable {
    public let report: ScanReport
    public let products: [NormalizedPluginProduct]
    public let daws: [InstalledDAWRecord]
    public let dawWarnings: [String]
    public let dawScopeNotes: [String]
}

public enum ScanPipeline {
    /// The cancellation handler explicitly owns the detached blocking scanner.
    public static func run(configuration: ScanConfiguration, scanDAWs: Bool,
                           dawConfiguration: DAWScanConfiguration = .standard) async throws -> StudioScanResult {
        try await CancellableWorker.run {
            let report = try PluginScanner().scan(configuration: configuration)
            try Task.checkCancellation()
            let dawResult = scanDAWs ? try DAWScanner().scanReport(configuration: dawConfiguration) : (records: [], warnings: [], scopeNotes: [])
            try Task.checkCancellation()
            let products = try ProductNormalizer().normalizeCancellable(records: report.records).products
            try Task.checkCancellation()
            return StudioScanResult(report: report, products: products, daws: dawResult.records, dawWarnings: dawResult.warnings, dawScopeNotes: dawResult.scopeNotes)
        }
    }
}

/// Shared ownership of cancellable blocking work; no detached task is left behind.
enum CancellableWorker {
    static func run<Value: Sendable>(_ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try operation()
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }
}
