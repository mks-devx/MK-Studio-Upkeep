// SPDX-License-Identifier: BUSL-1.1
import Combine
import Foundation

/// A previous selection's slow or cancelled read must never label the current selection.
@MainActor final class LatestDetailReading<Value: Sendable>: ObservableObject {
    @Published private(set) var value: Value?
    private var requestID = UUID()

    func read(_ operation: @Sendable () async -> Value) async {
        let request = UUID()
        requestID = request
        value = nil
        let result = await operation()
        guard !Task.isCancelled, request == requestID else { return }
        value = result
    }
}
