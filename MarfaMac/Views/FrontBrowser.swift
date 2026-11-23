import AppKit

/// The window of MAPP that was in front last, which a shortcut pressed in another app acts in. It is kept weakly and never
/// cleared when the window goes behind, since the person was in it before they went to the other app.
@MainActor
final class FrontBrowser {
    static let shared = FrontBrowser()

    weak var last: Browser?

    /// Brings MAPP forward and does the command's action in the window that was in front. With no such window, or no
    /// library to act on, it only brings MAPP forward.
    func perform(_ command: AnyAppCommand, in libraries: Libraries) {
        NSApp.activate()
        guard let browser = last, let library = libraries.current else { return }
        switch command {
        case .commandPalette: browser.palette = .commands
        case .searchItems: browser.palette = .search
        case .quickAdd:
            guard library.isLoaded else { return }
            browser.openQuickAdd(remembered: UserDefaults.standard.string(forKey: QuickAdd.lastTypeKey), in: library)
        }
    }
}
