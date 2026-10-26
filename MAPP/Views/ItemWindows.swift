import AppKit

/// Opening items in windows of their own, one window for each. Many at once is rarely meant, so past a few the
/// person is asked first.
@MainActor
enum ItemWindows {
    /// More windows than this are asked about first.
    static let confirmationThreshold = 10

    static func needsConfirmation(_ count: Int) -> Bool { count > confirmationThreshold }

    /// Opens a window for each of `ids`, in order, or asks first when there are many and opens none if the person declines.
    static func open(
        _ ids: [ItemID], asking confirm: @MainActor (_ count: Int, _ proceed: @escaping () -> Void) -> Void = ask,
        opening open: @escaping (ItemID) -> Void
    ) {
        guard !ids.isEmpty else { return }
        if needsConfirmation(ids.count) {
            confirm(ids.count) { for id in ids { open(id) } }
        } else {
            for id in ids { open(id) }
        }
    }

    /// A plain alert, as a sheet on the window in front where there is one.
    private static func ask(_ count: Int, _ proceed: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Open \(count) windows?")
        alert.informativeText = String(localized: "Each item opens in a window of its own.")
        alert.addButton(withTitle: String(localized: "Open"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { proceed() } }
        } else if alert.runModal() == .alertFirstButtonReturn {
            proceed()
        }
    }
}
