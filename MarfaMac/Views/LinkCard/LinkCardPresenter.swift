import AppKit
import SwiftUI

/// Where a card goes: the frame of the link it is for, in screen coordinates, and the window that link is in.
struct LinkCardAnchor {
    let rect: CGRect
    weak var window: NSWindow?
}

/// A panel that is never the key or the main window, so the card cannot take the keyboard from the page or the list.
private final class LinkCardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The card under the pointer on a linked item, for the whole app: one card at a time, drawn after the pointer has rested
/// on a link for `delay`, in a panel that takes no mouse or key and goes at once on a scroll, a key, a click, or when the
/// app or the window stops being the one the person is in. It asks Marfa for nothing: the counts it draws are the answers
/// `ItemCounts` already holds, wanted while the card shows and let go when it goes, never while it draws.
@MainActor
final class LinkCardPresenter {
    static let shared = LinkCardPresenter()
    /// How long the pointer rests on a link before its card shows.
    static let delay = Duration.milliseconds(600)

    private struct Shown {
        let id: ItemID
        let library: any ItemLibrary
        let queries: [CountQuery]
        let panel: LinkCardPanel
        let hosting: NSHostingView<LinkCardView>
        var anchor: LinkCardAnchor
    }

    private var waiting: Task<Void, Never>?
    private var shown: Shown?
    private var monitor: Any?
    private var observers: [any NSObjectProtocol] = []

    /// Waits for the pointer to rest, then shows the card of the item `resolve` names, if it names one the library can
    /// show. A new rest, or `end()`, drops one still waiting.
    func rest(library: any ItemLibrary, at anchor: LinkCardAnchor, after delay: Duration = delay, resolve: @escaping @MainActor () async -> ItemID?) {
        end()
        watchForEnd()
        waiting = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let id = await resolve(), !Task.isCancelled else { return }
            self?.show(id, library: library, at: anchor)
        }
    }

    /// Shows the card now, as the row's menu asks for it. VoiceOver is told what it says, since a card that takes no focus
    /// is otherwise never read.
    func show(_ id: ItemID, library: any ItemLibrary, at anchor: LinkCardAnchor, announcing: Bool = false) {
        waiting?.cancel()
        waiting = nil
        if let held = shown {
            tearDown(held)
            shown = nil
        }
        guard let content = LinkCardView.content(of: id, in: library), let window = anchor.window else { return }
        watchForEnd()
        let queries = library.cardItem(id).map { LinkCardContent.counts(for: $0, in: library.catalogue) } ?? []
        for query in queries { library.counts.want([id], query) }
        let size = UserDefaults.standard.object(forKey: InterfaceKey.textSize) as? Int ?? InterfaceStyle.defaultTextSize
        let hosting = NSHostingView(rootView: LinkCardView(id: id, library: library, textSize: size))
        hosting.setAccessibilityElement(announcing)
        let panel = LinkCardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentView = hosting
        shown = Shown(id: id, library: library, queries: queries, panel: panel, hosting: hosting, anchor: anchor)
        window.addChildWindow(panel, ordered: .above)
        place()
        panel.orderFront(nil)
        followCounts()
        if announcing {
            NSAccessibility.post(
                element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: ([content.typeName, content.title] + content.lines).joined(separator: ", ")])
        }
    }

    /// Shows the card now under a view's frame in its window's content (top left, as SwiftUI gives it), as a row's menu asks.
    func show(_ id: ItemID, library: any ItemLibrary, inWindowFrame frame: CGRect, announcing: Bool = false) {
        guard let window = NSApp.keyWindow, let content = window.contentView else { return }
        let local = CGRect(x: frame.minX, y: content.bounds.height - frame.maxY, width: frame.width, height: frame.height)
        show(id, library: library, at: LinkCardAnchor(rect: window.convertToScreen(content.convert(local, to: nil)), window: window), announcing: announcing)
    }

    /// Removes the card, or drops the wait for one.
    func end() {
        waiting?.cancel()
        waiting = nil
        guard let held = shown else { return stopWatching() }
        shown = nil
        tearDown(held)
        stopWatching()
    }

    private func tearDown(_ held: Shown) {
        for query in held.queries { held.library.counts.release([held.id], query) }
        held.anchor.window?.removeChildWindow(held.panel)
        held.panel.orderOut(nil)
    }

    /// Sizes the panel to the card and puts it under the link, or over it where the screen has no room below.
    private func place() {
        guard let held = shown else { return }
        let size = held.hosting.fittingSize
        let rect = held.anchor.rect
        let visible = (held.anchor.window?.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        var origin = CGPoint(x: rect.minX, y: rect.minY - 6 - size.height)
        if origin.y < visible.minY { origin.y = rect.maxY + 6 }
        origin.x = min(max(origin.x, visible.minX + 8), max(visible.minX + 8, visible.maxX - size.width - 8))
        held.panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    /// An answer from Marfa changes the lines, and with them the card's size.
    private func followCounts() {
        guard let held = shown else { return }
        let id = held.id
        withObservationTracking {
            _ = held.library.counts.revision
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.shown?.id == id else { return }
                self.place()
                self.followCounts()
            }
        }
    }

    // MARK: Going

    private func watchForEnd() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.end() }
            return event
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // The card's own panel resizing or moving is not the person leaving.
                if note.object is LinkCardPanel { return }
                MainActor.assumeIsolated { self?.end() }
            })
        }
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }
}
