// SPDX-License-Identifier: BUSL-1.1
import Foundation

public struct VendorManager: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let productPrefixes: [String]
    public let officialURL: URL
    public let uninstallURL: URL
    public let uninstallDetail: String

    public static let known: [VendorManager] = [
        VendorManager(id: "antelope-audio", name: "Antelope Launcher",
            productPrefixes: ["com.antelopeaudio."],
            officialURL: URL(string: "https://support.antelopeaudio.com/en/support/solutions/articles/42000111514-downloads")!,
            uninstallURL: URL(string: "https://support.antelopeaudio.com/en/support/home")!,
            uninstallDetail: "Review firmware and driver availability in Antelope Launcher. Ask Antelope support for device-specific driver removal; removing the launcher is not the same as uninstalling the driver."),
        VendorManager(id: "native-instruments", name: "Native Access",
            productPrefixes: ["com.native-instruments."],
            officialURL: URL(string: "https://www.native-instruments.com/pages/native-access")!,
            uninstallURL: URL(string: "https://support.native-instruments.com/support/solutions/articles/69000879356-how-to-uninstall-native-instruments-software-from-a-mac-computer")!,
            uninstallDetail: "Native Access supports uninstalling some content products. Programs and plugins may need the official manual instructions. Keep libraries and licences unless you explicitly intend to remove them."),
        VendorManager(id: "ik-multimedia", name: "IK Product Manager",
            productPrefixes: ["com.ikmultimedia."],
            officialURL: URL(string: "https://www.ikmultimedia.com/products/productmanager/")!,
            uninstallURL: URL(string: "https://www.ikmultimedia.com/support/")!,
            uninstallDetail: "Use IK Product Manager to review software, sounds and firmware updates. In-manager uninstall support is not confirmed for every product; consult IK support before removing shared content.")
    ]

    public static func matching(identifiers: [String]) -> VendorManager? {
        guard !identifiers.isEmpty else { return nil }
        return known.first { manager in
            identifiers.allSatisfy { id in manager.productPrefixes.contains { id.lowercased().hasPrefix($0) } }
        }
    }
}
