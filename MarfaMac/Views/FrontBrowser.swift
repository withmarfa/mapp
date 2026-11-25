import AppKit

/// The window of the app that was in front last, which a shortcut pressed in another app acts in. It is kept weakly and never
/// cleared when the window goes behind, since the person was in it before they went to the other app.
@MainActor
final class FrontBrowser {
    static let shared = FrontBrowser()

    weak var last: Browser?

    /// Does the command's action. A palette brings the app forward and opens in the window that was in front, or only
    /// brings the app forward with no such window or no library. New Item opens the line over the other app
    /// (`NewItemAnywhere`), which never brings the app forward.
    func perform(_ command: AnyAppCommand, in libraries: Libraries) {
        if command == .newItem {
            NewItemAnywhere.shared.show(in: libraries)
            return
        }
        NSApp.activate()
        guard let browser = last, libraries.current != nil else { return }
        switch command {
        case .commandPalette: browser.palette = .commands
        case .searchItems: browser.palette = .search
        case .newItem: break
        }
    }
}
