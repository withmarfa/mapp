import AppKit

/// The window of the app that was in front last, which a shortcut pressed in another app acts in. It is kept weakly and never
/// cleared when the window goes behind, since the person was in it before they went to the other app.
@MainActor
final class FrontBrowser {
    static let shared = FrontBrowser()

    weak var last: Browser?
    /// Opens a main window. A window's view sets it, as only a view can open one.
    var openMainWindow: (() -> Void)?
    /// A draft the line over another app handed to the text form while no window could take it, for the next main
    /// window to show it.
    private var handed: (draft: UUID, library: () -> (any ItemLibrary)?)?

    /// Brings the app forward with `draft` in a window's text form: the window last in front where it holds no draft
    /// with anything typed, else a new main window, so neither draft is lost or opened in the other's place. Until a
    /// window takes it, the draft stays kept (`NewItemDrafts`).
    func hand(_ draft: UUID, in library: any ItemLibrary) {
        NSApp.activate()
        if let last, last.openHandedNewItem(draft, in: library) { return }
        handed = (draft, { [weak library] in library })
        openMainWindow?()
    }

    /// Shows the draft handed while no window could take it, in `browser`'s window once it has restored.
    func takeHanded(into browser: Browser, in library: any ItemLibrary) {
        guard let handed, let meant = handed.library(), meant === library else { return }
        if browser.openHandedNewItem(handed.draft, in: library) { self.handed = nil }
    }

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
