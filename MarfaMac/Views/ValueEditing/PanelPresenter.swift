import AppKit

/// One open panel under a view, which `PanelPresenter` keeps and watches: a value's editor (`ValueEditSession`) or a
/// filter's panel (`FilterPanelSession`). What differs between them is here, and nothing else does.
@MainActor
protocol PanelSession: AnyObject {
    /// What the panel is for. The click that closes a panel does not open the same target again.
    var target: String { get }
    /// The window the panel draws in, which clicks inside are not "outside".
    var window: NSWindow? { get }
    var anchor: NSView { get }
    /// Shows the panel.
    func open()
    /// Puts it away. `restoringFocus` gives the keyboard back to where it was in the window the panel came from.
    func close(restoringFocus: Bool)
    /// The anchor, or a view above it, or its window moved: follow it.
    func anchorMoved()
    /// The panel is ending, before it goes: write what it holds, or hand it back, unless the person `cancelled` it.
    func finish(cancelled: Bool)
    /// A key pressed in the panel, other than Escape, which always closes it. Whether the panel took it.
    func handleKey(_ event: NSEvent) -> Bool
}

/// Keeps at most one panel open under a view, whoever asks, and closes it as the system closes a menu: a click outside, the
/// window under it moving, resizing or closing, the app going to the background, or the page or sidebar scrolling.
/// Escape closes it too. The panel follows its anchor, and every view above it, as they move.
@MainActor
final class PanelPresenter {
    private(set) var session: (any PanelSession)?
    /// A click on the target while its panel is open closes it as an outside click; the click then asks to open it
    /// again, which would put it straight back. The target toggles instead.
    private var closedByClick: (target: String, at: Date)?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    var isOpen: Bool { session != nil }

    /// Whether the panel open is for `target`.
    func isOpen(for target: String) -> Bool { session?.target == target }

    /// Opens the panel `make` builds for `target` under `anchor`, or closes it where it is the panel already open or was
    /// just closed by the click that asks to open it. Nothing opens where `make` gives none, or `anchor` has no window yet.
    func present(target: String, anchor: NSView?, now: Date = .now, make: (NSView) -> (any PanelSession)?) {
        if let session {
            let same = session.target == target
            dismiss()
            if same { return }
        }
        if let closed = closedByClick {
            closedByClick = nil
            if closed.target == target, now.timeIntervalSince(closed.at) < 0.4 { return }
        }
        guard let anchor, anchor.window != nil, let new = make(anchor) else { return }
        session = new
        new.open()
        watch(new)
    }

    /// Closes the panel open, if any. What was typed in it is written or handed back (`PanelSession.finish`) unless the
    /// person `cancelled` it, with Escape.
    func dismiss(restoringFocus: Bool = true, cancelled: Bool = false) {
        guard let closing = session else { return }
        session = nil
        unwatch()
        closing.finish(cancelled: cancelled)
        closing.close(restoringFocus: restoringFocus)
    }

    // MARK: Watching

    private func watch(_ session: any PanelSession) {
        let center = NotificationCenter.default
        // A row that moves with its panel open, as a value's row does once it holds a value, takes the panel along. SwiftUI
        // moves the view that holds the anchor, not the anchor in it, so every view above it is watched too.
        var ancestor: NSView? = session.anchor
        while let view = ancestor {
            view.postsFrameChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.session?.anchorMoved() }
            })
            ancestor = view.superview
        }
        if let parent = session.anchor.window {
            observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.session?.anchorMoved() }
            })
            for name in [NSWindow.didResizeNotification, NSWindow.willCloseNotification, NSWindow.didEndLiveResizeNotification] {
                observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismiss(restoringFocus: false) }
                })
            }
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoringFocus: false) }
        })
        let outside: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: outside.union([.scrollWheel, .keyDown]), handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? false } ? nil : event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: outside, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoringFocus: false) }
        }) { monitors.append(monitor) }
    }

    private func unwatch() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// Whether the panel took the event, which then goes no further.
    private func handle(_ event: NSEvent) -> Bool {
        guard let session else { return false }
        let inside = session.window != nil && event.window === session.window
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if !inside {
                closedByClick = (session.target, .now)
                dismiss(restoringFocus: false)
            }
        case .scrollWheel:
            // The list in the panel scrolls itself; the page or sidebar under it takes the panel away.
            if !inside, event.window === session.anchor.window { dismiss(restoringFocus: true) }
        case .keyDown where inside:
            if event.keyCode == 53 {
                dismiss(cancelled: true)
                return true
            }
            return session.handleKey(event)
        default:
            break
        }
        return false
    }
}
