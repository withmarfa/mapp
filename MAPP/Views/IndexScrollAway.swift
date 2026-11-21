import AppKit
import SwiftUI

/// How far an index page's table has scrolled, which only the block of the page's header reads. A model of its own, so
/// a scroll redraws that one view and no other.
@MainActor @Observable
final class IndexScroll {
    /// How far the rows have scrolled from the first, never below zero.
    var offset: CGFloat = 0
}

/// What the table behind an index page needs of the page above it: the height of the block it leaves room for, how far
/// it has to scroll before the title and tabs are gone, and where to say so.
struct IndexScrollMetrics {
    var scroll: IndexScroll?
    var blockHeight: CGFloat = 0
    var awayAt: CGFloat = 0
    var report: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var indexScroll = IndexScrollMetrics()
}

/// An index page: a block of header (the title and tabs, then the New row or the filter row) that scrolls away with the
/// rows, over a table whose column headings then stay pinned under the toolbar. The table is one `NSScrollView`, so the
/// block is not in it: the table leaves room for it as a top inset (`indexScrollsAway`) and this view draws the block
/// over that room, moved up by as much as the rows have scrolled. Where the page has no table, the content leaves the
/// room itself, from the height it is handed.
struct IndexScaffold<Top: View, Extra: View, Content: View>: View {
    /// Told whether the title and tabs have scrolled out of view.
    let onAway: (Bool) -> Void
    @ViewBuilder let top: Top
    @ViewBuilder let extra: Extra
    @ViewBuilder let content: (CGFloat) -> Content
    @State private var scroll = IndexScroll()
    @State private var blockHeight: CGFloat = 0
    @State private var topHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            content(blockHeight)
                .environment(\.indexScroll, IndexScrollMetrics(scroll: scroll, blockHeight: blockHeight, awayAt: topHeight, report: onAway))
            IndexHeaderBlock(scroll: scroll, height: blockHeight) {
                VStack(spacing: 0) {
                    top.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
                    extra
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { blockHeight = $0 }
            }
        }
        .frame(maxWidth: .infinity)
        .background { Color(nsColor: IndexMetrics.backdrop).ignoresSafeArea() }
        .onChange(of: blockHeight == 0) { if blockHeight == 0 { onAway(false) } }
    }
}

/// The header block over the room the table leaves, moved up as the rows scroll and clipped to that room, so it never
/// draws over the toolbar or the pinned headings.
private struct IndexHeaderBlock<Block: View>: View {
    let scroll: IndexScroll
    let height: CGFloat
    @ViewBuilder let block: Block

    var body: some View {
        block
            .fixedSize(horizontal: false, vertical: true)
            .offset(y: -min(scroll.offset, height))
            .frame(height: height, alignment: .top)
            .clipped()
    }
}

extension View {
    /// Makes this table's room at the top for the page's header block, and pins its column headings under the toolbar
    /// once the rows have scrolled past that room. Attach it to the `Table` inside an `IndexScaffold`.
    func indexScrollsAway() -> some View {
        modifier(IndexScrollsAway())
    }
}

private struct IndexScrollsAway: ViewModifier {
    @Environment(\.indexScroll) private var metrics

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectHidden(true, for: .top)
            .background { IndexScrollProbe(metrics: metrics) }
    }
}

/// Reaches the `NSScrollView` behind a table. SwiftUI's `contentMargins` leaves a `Table`'s scroll view alone, so the
/// room for the header block is the scroll view's own top inset; AppKit adds the headings' height to it. The headings'
/// container is then set at the toolbar's lower edge, or lower while the block still shows, and set again whenever the
/// scroll view or AppKit moves it.
private struct IndexScrollProbe: NSViewRepresentable {
    let metrics: IndexScrollMetrics

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.metrics = metrics
        probe.refresh()
    }

    static func dismantleNSView(_ probe: Probe, coordinator: ()) {
        probe.stop()
    }

    final class Probe: NSView {
        var metrics = IndexScrollMetrics()
        private weak var table: NSTableView?
        private var observers: [any NSObjectProtocol] = []
        private var isPlacing = false
        private var isAway = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refresh()
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }

        override func layout() {
            super.layout()
            refresh()
        }

        func refresh() {
            guard window != nil, let table = nearestTable(), let scroll = table.enclosingScrollView else { return }
            if self.table !== table { follow(table, in: scroll) }
            let room = scroll.safeAreaInsets.top + metrics.blockHeight
            if scroll.automaticallyAdjustsContentInsets { scroll.automaticallyAdjustsContentInsets = false }
            if scroll.contentInsets.top != room {
                let clip = scroll.contentView
                let scrolled = clip.bounds.origin.y + clip.contentInsets.top
                var insets = scroll.contentInsets
                insets.top = room
                scroll.contentInsets = insets
                // Keeps the rows where they were: the same distance from the first, and the same sideways place.
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: scrolled - clip.contentInsets.top))
                scroll.reflectScrolledClipView(clip)
            }
            place()
        }

        private func follow(_ table: NSTableView, in scroll: NSScrollView) {
            stop()
            self.table = table
            scroll.contentView.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.place() } })
            if let container = table.headerView?.superview {
                container.postsFrameChangedNotifications = true
                // AppKit tiles the headings again when the scroll view lays out, which would undo the pinning.
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: container, queue: .main
                ) { [weak self] _ in MainActor.assumeIsolated { self?.place() } })
            }
        }

        func stop() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            let wasAway = isAway
            isAway = false
            metrics.scroll?.offset = 0
            if wasAway { metrics.report(false) }
        }

        private func place() {
            guard !isPlacing, let table, let scroll = table.enclosingScrollView, let container = table.headerView?.superview else { return }
            let clip = scroll.contentView
            let scrolled = max(0, clip.bounds.origin.y + clip.contentInsets.top)
            if let model = metrics.scroll, model.offset != scrolled { model.offset = scrolled }
            let away = metrics.blockHeight > 0 && scrolled >= metrics.awayAt && metrics.awayAt > 0
            if away != isAway {
                isAway = away
                metrics.report(away)
            }
            let top = scroll.safeAreaInsets.top + max(0, metrics.blockHeight - scrolled)
            if container.frame.origin.y != top {
                isPlacing = true
                container.frame.origin.y = top
                isPlacing = false
            }
        }
    }
}
