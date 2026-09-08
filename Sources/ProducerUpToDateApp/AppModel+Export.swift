// SPDX-License-Identifier: MPL-2.0
import AppKit
import ProducerUpToDateCore
import UniformTypeIdentifiers

/// Local inventory export. The user picks the file and whether paths are included; nothing
/// leaves the Mac and the home folder is never spelled out.
extension AppModel {
    func exportInventory() {
        guard currentReport != nil else { return }
        let panel = NSSavePanel()
        panel.title = "Export inventory"
        panel.nameFieldStringValue = "MK Studio Upkeep inventory.csv"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.canCreateDirectories = true
        let pathsToggle = NSButton(checkboxWithTitle: "Include file paths (home folder shown as ~)", target: nil, action: nil)
        pathsToggle.state = .off
        panel.accessoryView = pathsToggle
        panel.message = "Plugins and DAWs from the last scan, as CSV (.csv) or plain text (.txt). Saved on this Mac only."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let includePaths = pathsToggle.state == .on
        let rows = InventoryExport.rows(plugins: pluginUpdateResults, daws: installedDAWs, localOnly: true)
        let content = url.pathExtension.lowercased() == "txt"
            ? InventoryExport.text(rows, includePaths: includePaths)
            : InventoryExport.csv(rows, includePaths: includePaths, localOnly: true)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "The inventory could not be saved"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
