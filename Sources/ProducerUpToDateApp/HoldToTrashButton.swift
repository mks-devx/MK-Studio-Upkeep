// SPDX-License-Identifier: BUSL-1.1
import AppKit
import ProducerUpToDateCore
import SwiftUI

/// Mouse or Space must remain held; releasing early, moving outside, Escape or
/// losing application focus cancels. Accessibility activation opens a separate
/// confirmation with the same minimum review time; it never deletes immediately.
struct HoldToTrashButton: NSViewRepresentable {
    let enabled: Bool
    var title = "Hold 5 seconds, then release to Trash"
    var readyTitle = "Release to move selected files to Trash"
    let action: () -> Void
    func makeNSView(context: Context) -> HoldButton { let button = HoldButton(); button.idleTitle = title; button.readyTitle = readyTitle; button.title = title; return button }
    func updateNSView(_ view: HoldButton, context: Context) {
        view.isEnabled = enabled
        view.confirm = action
        view.idleTitle = title
        view.readyTitle = readyTitle
        view.setAccessibilityLabel(title)
        if !view.isHighlighted { view.title = title }
    }
    final class HoldButton: NSButton {
        var confirm: (() -> Void)?
        var idleTitle = "Hold 5 seconds, then release to Trash"
        var readyTitle = "Release to move selected files to Trash"
        init() {
            super.init(frame: .zero)
            title = "Hold 5 seconds, then release to Trash"
            bezelStyle = .rounded
            setAccessibilityLabel(title)
            setAccessibilityHelp("Hold the mouse button or Space for five seconds, then release. Release early or press Escape to cancel. Assistive activation opens a separate confirmation dialog.")
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var acceptsFirstResponder: Bool { true }
        private var presentingConfirmation = false
        override func accessibilityPerformPress() -> Bool {
            guard isEnabled, !presentingConfirmation, window != nil else { return false }
            presentingConfirmation = true
            defer { presentingConfirmation = false }
            let alert = NSAlert()
            alert.messageText = "Confirm the selected action"
            alert.informativeText = readyTitle.replacingOccurrences(of: "Release to ", with: "")
                + ". Review the selected items before confirming. You can cancel without changing anything."
            alert.alertStyle = .warning
            let cancel = alert.addButton(withTitle: "Cancel")
            cancel.keyEquivalent = "\r"
            let accept = alert.addButton(withTitle: "Please wait…")
            accept.keyEquivalent = ""
            accept.isEnabled = false
            let start = ProcessInfo.processInfo.systemUptime
            let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    if HoldToConfirmPolicy.permits(start: start, end: ProcessInfo.processInfo.systemUptime, cancelled: false) {
                        accept.title = "Confirm"
                        accept.isEnabled = true
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            defer { timer.invalidate() }
            let response = alert.runModal()
            if response == .alertSecondButtonReturn, isEnabled,
               HoldToConfirmPolicy.permits(start: start, end: ProcessInfo.processInfo.systemUptime, cancelled: false) {
                confirm?()
            }
            return true
        }
        override func mouseDown(with event: NSEvent) { trackHold(keyboard: false) }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 49 && !event.isARepeat { trackHold(keyboard: true) }
            else { super.keyDown(with: event) }
        }
        private func trackHold(keyboard: Bool) {
            guard isEnabled, let window else { return }
            let start = ProcessInfo.processInfo.systemUptime
            var cancelled = false
            var released = false
            highlight(true)
            defer { title = idleTitle; highlight(false) }
            while !released && !cancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                title = elapsed >= 5 ? readyTitle : "Keep holding… \(max(1, Int(ceil(5 - elapsed))))"
                guard NSApp.isActive, window.isKeyWindow, isEnabled else { cancelled = true; break }
                guard let event = NSApp.nextEvent(matching: [.leftMouseUp, .leftMouseDragged, .keyUp, .keyDown],
                    until: Date(timeIntervalSinceNow: 0.05), inMode: .eventTracking, dequeue: true) else { continue }
                if event.type == .keyDown && event.keyCode == 53 { cancelled = true }
                else if keyboard && event.type == .keyUp && event.keyCode == 49 { released = true }
                else if !keyboard && event.type == .leftMouseUp {
                    released = true
                    cancelled = !bounds.contains(convert(event.locationInWindow, from: nil))
                } else if !keyboard && event.type == .leftMouseDragged {
                    cancelled = !bounds.contains(convert(event.locationInWindow, from: nil))
                }
            }
            if released && HoldToConfirmPolicy.permits(start: start, end: ProcessInfo.processInfo.systemUptime, cancelled: cancelled) {
                confirm?()
            }
        }
    }
}
