// SPDX-License-Identifier: MPL-2.0
// Native sheet interaction regression. Actions only increment a counter; no files are removed.
import AppKit
import SwiftUI

@main @MainActor struct HoldInteractionCheck {
    private static var called = 0
    private static var started = false
    private static var sheet: NSWindow!
    private static var button: HoldToTrashButton.HoldButton!

    static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let parent = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
                             styleMask: [.titled], backing: .buffered, defer: false)
        button = HoldToTrashButton.HoldButton()
        button.frame = NSRect(x: 30, y: 30, width: 340, height: 32)
        sheet.contentView!.addSubview(button)
        parent.makeKeyAndOrderFront(nil)
        parent.beginSheet(sheet)
        app.activate(ignoringOtherApps: true)
        button.confirm = { called += 1 }
        let start = Timer(timeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard app.isActive, sheet.isKeyWindow, !started else { return }
                started = true
                attempt("mouse hold then release", delay: 5.2, expected: 1) { app.postEvent(mouse(.leftMouseUp), atStart: false) }
                attempt("early release cancels", delay: 0.1, expected: 0) { app.postEvent(mouse(.leftMouseUp), atStart: false) }
                attempt("drag outside cancels", delay: 0.1, expected: 0) { app.postEvent(mouse(.leftMouseDragged, outside: true), atStart: false) }
                attempt("Escape cancels", delay: 0.1, expected: 0) { app.postEvent(key(.keyDown, code: 53), atStart: false) }
                attempt("disabled during hold cancels", delay: 0.1, expected: 0) { button.isEnabled = false }
                button.isEnabled = true
                attempt("Space hold then release", delay: 5.2, keyboard: true, expected: 1) { app.postEvent(key(.keyUp, code: 49), atStart: false) }
                attempt("early Space release cancels", delay: 0.1, keyboard: true, expected: 0) { app.postEvent(key(.keyUp, code: 49), atStart: false) }
                button.isEnabled = false
                button.mouseDown(with: mouse(.leftMouseDown))
                precondition(called == 2)
                print("PASS: disabled control cannot activate; 8 native sheet cases; synthetic callbacks only")
                exit(0)
            }
        }
        RunLoop.main.add(start, forMode: .common)
        app.run()
    }

    private static func mouse(_ type: NSEvent.EventType, outside: Bool = false) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: outside ? -20 : 100, y: 45),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: sheet.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    private static func key(_ type: NSEvent.EventType, code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber,
            context: nil, characters: code == 49 ? " " : "\u{1b}", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code)!
    }
    private static func attempt(_ name: String, delay: Double, keyboard: Bool = false,
                 expected: Int, finish: @escaping @MainActor @Sendable () -> Void) {
        let before = called
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { finish() }
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        if keyboard { button.keyDown(with: key(.keyDown, code: 49)) }
        else { button.mouseDown(with: mouse(.leftMouseDown)) }
        timer.invalidate()
        precondition(called - before == expected, name)
        precondition(!button.isHighlighted && button.title == button.idleTitle)
        print("PASS: \(name)")
    }
}
