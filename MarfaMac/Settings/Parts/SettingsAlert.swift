import AppKit

/// The system's alert for a question before something that can't be undone, with an optional checkbox for a choice that
/// goes with it. Cancel is the default button; the confirming one is destructive. SwiftUI's `alert` has no checkbox.
@MainActor enum SettingsAlert {
    /// Asks on `window`, or on its own where there is none, and answers whether the person confirmed and whether they
    /// ticked the box (always false without one).
    static func confirm(
        title: String, message: String, confirm: String, checkbox: String? = nil, window: NSWindow?,
        answer: @escaping (_ confirmed: Bool, _ checked: Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "Cancel"))
        let confirming = alert.addButton(withTitle: confirm)
        confirming.hasDestructiveAction = true
        if let checkbox {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = checkbox
            alert.suppressionButton?.state = .off
            alert.suppressionButton?.setAccessibilityIdentifier("SettingsAlertCheckbox")
        }
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            answer(response == .alertSecondButtonReturn, alert.suppressionButton?.state == .on)
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}
