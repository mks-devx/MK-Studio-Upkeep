// SPDX-License-Identifier: BUSL-1.1
// Native modal confirmation smoke test; callbacks never touch files.
import AppKit
import SwiftUI
@main struct ConfirmationCheck {
 @MainActor static func main() {
  let app = NSApplication.shared
  app.setActivationPolicy(.regular)
  let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
  let button = HoldToTrashButton.HoldButton()
  window.contentView = button
  window.makeKeyAndOrderFront(nil)
  app.activate(ignoringOtherApps: true)
  var called = 0
  button.confirm = { called += 1 }
  func attempt(after delay: Double, response: NSApplication.ModalResponse) {
   let timer = Timer(timeInterval: delay, repeats: false) { _ in
    MainActor.assumeIsolated { app.stopModal(withCode: response) }
   }
   RunLoop.main.add(timer, forMode: .modalPanel)
   precondition(button.accessibilityPerformPress())
   timer.invalidate()
  }
  attempt(after: 0.2, response: .alertFirstButtonReturn)
  precondition(called == 0, "Cancel must not execute")
  attempt(after: 0.2, response: .alertSecondButtonReturn)
  precondition(called == 0, "Early confirmation must not execute")
  attempt(after: 5.3, response: .alertSecondButtonReturn)
  precondition(called == 1, "Delayed explicit confirmation must execute once")
  button.isEnabled = false
  precondition(!button.accessibilityPerformPress())
  precondition(called == 1)
  print("PASS: cancellation, early rejection, delayed confirmation, disabled state; synthetic callback only")
 }
}
