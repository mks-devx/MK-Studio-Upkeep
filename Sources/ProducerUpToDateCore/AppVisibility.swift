// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// There must always be a visible way to reopen the application.
public struct AppVisibility: Equatable, Sendable {
    public let dock: Bool
    public let menuBar: Bool
    public init(dock: Bool, menuBar: Bool) {
        self.dock = dock || !menuBar
        self.menuBar = menuBar
    }
}
