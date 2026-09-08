// SPDX-License-Identifier: MPL-2.0
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
