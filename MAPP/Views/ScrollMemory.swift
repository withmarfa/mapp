import AppKit
import SwiftUI

extension View {
    /// Starts the list this is applied to where the last one was scrolled, and keeps `memory` current as it scrolls.
    /// SwiftUI's own scroll position does not move a `List` on macOS, so this finds the table behind it, as
    /// `softSelection` does.
    func remembersScroll(in memory: SidebarMemory) -> some View {
        background(ScrollMemory(memory: memory))
    }
}

struct ScrollMemory: NSViewRepresentable {
    let memory: SidebarMemory

    func makeNSView(context: Context) -> Probe { Probe(memory: memory) }
    func updateNSView(_ probe: Probe, context: Context) {}
    static func dismantleNSView(_ probe: Probe, coordinator: ()) { probe.stop() }

    final class Probe: NSView {
        private let memory: SidebarMemory
        private var observer: NSObjectProtocol?
        private var isWatching = false

        init(memory: SidebarMemory) {
            self.memory = memory
            super.init(frame: .zero)
            memory.rearm = { [weak self] in self?.rearm() }
            memory.rearmOwner = ObjectIdentifier(self)
        }

        private func rearm() {
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            isWatching = false
            if restore() { watch() }
        }

        /// The list's scroll view, or the one the probe sits inside for a column that is not a list.
        private func scrollView() -> NSScrollView? { nearestTable()?.enclosingScrollView ?? enclosingScrollView }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            restore()
            // The table may not hold its rows yet, so there is nothing to scroll to; the offset is tried again once
            // the pass is done, and only then does the list's own scrolling count.
            DispatchQueue.main.async { [weak self] in
                self?.restore()
                self?.watch()
            }
        }

        override func layout() {
            super.layout()
            // Once the offset is reached, or there is none to reach, the list's own scrolling counts, so a later layout
            // never scrolls it back over the person's.
            if restore() { watch() }
        }

        /// Whether the list now shows the remembered offset, or has none to show.
        @discardableResult
        private func restore() -> Bool {
            guard !isWatching, window != nil, let scroll = scrollView() else { return false }
            guard let offset = memory.scrollOffset, offset > 0 else { return true }
            let clip = scroll.contentView
            let room = (scroll.documentView?.frame.height ?? 0) - clip.bounds.height
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: min(offset, max(room, 0))))
            scroll.reflectScrolledClipView(clip)
            return room >= offset
        }

        private func watch() {
            guard !isWatching, let clip = scrollView()?.contentView else { return }
            isWatching = true
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // A list being taken down can reset its clip view to the top; that is no scroll of the person's.
                    guard let self, self.window != nil else { return }
                    self.memory.scrollOffset = clip.bounds.origin.y
                    self.memory.scrolled?()
                }
            }
        }

        func stop() {
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            if memory.rearmOwner == ObjectIdentifier(self) {
                memory.rearm = nil
                memory.rearmOwner = nil
            }
        }
    }
}
