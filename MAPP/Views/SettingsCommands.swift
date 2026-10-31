import SwiftUI

/// A request made with no focused main window is consumed by the main window the command opens.
@Observable
final class SettingsRequest {
    var isPending = false
    /// The page the request asked for; nil keeps the page shown last.
    var page: SettingsPage?

    /// A main window that is open, so Settings asked for from an item's window goes to it, not to another window.
    private struct MainWindow {
        weak var browser: Browser?
        weak var window: NSWindow?
    }
    @ObservationIgnored private var mainWindows: [MainWindow] = []

    /// Notes that `browser` is shown in `window`, a main window.
    func register(_ browser: Browser, in window: NSWindow?) {
        mainWindows.removeAll { $0.browser == nil || $0.browser === browser }
        mainWindows.append(MainWindow(browser: browser, window: window))
    }

    /// The browser of the main window in front of the others, if any is open.
    private var frontMainWindow: MainWindow? {
        // A window that was closed is no main window to show Settings in, whether or not its browser lives on.
        mainWindows.removeAll { main in
            guard main.browser != nil else { return true }
            guard let window = main.window else { return false }
            return !window.isVisible && !window.isMiniaturized
        }
        let ordered = NSApp?.orderedWindows ?? []
        return ordered.lazy.compactMap { window in self.mainWindows.first { $0.window === window } }.first ?? mainWindows.last
    }

    /// Shows Settings in `browser`'s window. Where the window in front has no browser, as an item's window has none,
    /// it shows Settings in a main window that is already open and brings it forward, and opens one only when none is.
    func show(_ page: SettingsPage? = nil, in browser: Browser?, openWindow: OpenWindowAction) {
        show(page, in: browser) { openWindow(id: "main") }
    }

    func show(_ page: SettingsPage?, in browser: Browser?, opening open: () -> Void) {
        if let browser {
            browser.showSettings(page)
        } else if let existing = frontMainWindow, let target = existing.browser {
            target.showSettings(page)
            if let window = existing.window {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            self.page = page
            isPending = true
            open()
        }
    }
}

extension View {
    /// Tells `request` that this view is a main window showing `browser`.
    func registersMainWindow(_ browser: Browser, with request: SettingsRequest) -> some View {
        background(WindowHandle { request.register(browser, in: $0) })
    }
}

/// Reports the window its view is in.
private struct WindowHandle: NSViewRepresentable {
    let found: (NSWindow?) -> Void

    func makeNSView(context: Context) -> Probe { Probe(found: found) }
    func updateNSView(_ probe: Probe, context: Context) { probe.found = found }

    final class Probe: NSView {
        var found: (NSWindow?) -> Void

        init(found: @escaping (NSWindow?) -> Void) {
            self.found = found
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found(window) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct SettingsCommands: Commands {
    let request: SettingsRequest
    @FocusedValue(\.browser) private var browser
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…", systemImage: "gearshape") {
                request.show(in: browser, openWindow: openWindow)
            }
            .keyboardShortcut(",")
        }
    }
}

/// An item's window tells the notices too, and has no browser, so a notice's way to Settings opens a main window.
struct ItemWindowNotices: ViewModifier {
    let notices: Notices
    let settingsRequest: SettingsRequest
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.notices(notices) { settingsRequest.show($0, in: nil, openWindow: openWindow) }
    }
}
