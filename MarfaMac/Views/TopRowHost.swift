import AppKit
import SwiftUI

/// How far the rows of a column have scrolled, which only the top row reads. A model of its own, so a scroll redraws
/// the row and no other view.
@MainActor @Observable
final class TopRowScroll {
    /// How far the rows have scrolled from the first, never below zero.
    var offset: CGFloat = 0
    /// The column headings' height, which a table's rows pass under before they reach the toolbar.
    var headingHeight: CGFloat = 0
}

/// What a list needs to know of the top row above it: the room the row of views takes at rest, which the list leaves
/// at its top, and where to say how far it has scrolled.
struct TopRowSpace {
    var scroll: TopRowScroll?
    var restHeight: CGFloat = 0
}

extension EnvironmentValues {
    @Entry var topRowSpace = TopRowSpace()
}

/// The room the toolbar's items take beside a column, measured from the window's own toolbar (`ToolbarRoomProbe`).
struct TopRowRoom: Equatable {
    /// How far into the column its leading toolbar items and the traffic lights reach, when they stand over it.
    var leading: CGFloat = 0
    /// How far into the column the buttons at its trailing edge reach.
    var trailing: CGFloat = 0
}

/// The top row over a column: the title's line at the height of the toolbar, the band the rows scroll under, and the
/// row of views at rest under the line. It is drawn over the column, so the toolbar holds only the buttons.
struct TopRowFrame<Line: View, Rest: View>: ViewModifier {
    @AppStorage(InterfaceKey.showsPageToolbarBackground) private var showsBackground = true
    @State private var toolbarHeight: CGFloat = 52
    @State private var room = TopRowRoom()
    let scroll: TopRowScroll?
    /// The room the row of views takes at rest, or zero where there is none.
    let restHeight: CGFloat
    /// Whether the row draws the band the rows scroll under. A page draws its own.
    let bands: Bool
    /// What changes the toolbar's items, so the room is measured again.
    let signal: AnyHashable
    /// The line, told whether the rows have scrolled past the row of views at rest.
    let line: (_ room: TopRowRoom, _ isAway: Bool) -> Line
    let rest: Rest

    init(
        scroll: TopRowScroll?, restHeight: CGFloat, bands: Bool, signal: AnyHashable,
        @ViewBuilder line: @escaping (_ room: TopRowRoom, _ isAway: Bool) -> Line, @ViewBuilder rest: () -> Rest
    ) {
        self.scroll = scroll
        self.restHeight = restHeight
        self.bands = bands
        self.signal = signal
        self.line = line
        self.rest = rest()
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { toolbarHeight = $0 }
            .background { ToolbarRoomProbe(room: $room, signal: signal) }
            .overlay(alignment: .top) {
                TopRowStack(
                    scroll: scroll, restHeight: restHeight, height: toolbarHeight, bands: bands && showsBackground, room: room,
                    line: line, rest: rest)
                .ignoresSafeArea(.container, edges: .top)
            }
    }
}

/// Apart from the frame so a scroll redraws this and not the column.
private struct TopRowStack<Line: View, Rest: View>: View {
    let scroll: TopRowScroll?
    let restHeight: CGFloat
    let height: CGFloat
    let bands: Bool
    let room: TopRowRoom
    let line: (TopRowRoom, Bool) -> Line
    let rest: Rest

    var body: some View {
        let offset = scroll?.offset ?? 0
        let isAway = restHeight == 0 || offset >= restHeight - 0.5
        let headings = scroll?.headingHeight ?? 0
        // The first row is as far below the toolbar as the row of views and the headings are tall.
        let isUnder = bands && offset > restHeight + headings + 0.5
        ZStack(alignment: .top) {
            ToolbarBand(toolbarHeight: height, isShown: isUnder)
            VStack(spacing: 0) {
                line(room, isAway)
                    .frame(height: height)
                    .background { TopRowDragArea() }
                if restHeight > 0, !isAway {
                    rest
                        .frame(height: restHeight, alignment: .top)
                        .offset(y: -min(offset, restHeight))
                        .frame(height: restHeight, alignment: .top)
                        .clipped()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

extension TopRowRoom {
    /// The title's inset at the column's start: the usual one, or further where the traffic lights, the sidebar's button
    /// and Back and Forward stand over it.
    var titleLead: CGFloat { max(TopRowMetrics.lead, leading > 0 ? leading + TopRowMetrics.clearance : 0) }
    /// What the line keeps for the buttons at the column's end.
    var titleTrail: CGFloat { max(14, trailing > 0 ? trailing + TopRowMetrics.clearance : 14) }
}

// MARK: Scrolling lists

extension View {
    /// Makes room at the top of a list, gallery, board or timeline for the row of views at rest, and tells the top row how
    /// far the rows have scrolled. The system's own edge is hidden, as the row draws the band. Attach it to the scroll view.
    func topRowScrolls() -> some View {
        modifier(TopRowScrolls())
    }

    /// The same for a table or a list, whose scroll view is AppKit's: a table's column headings stay pinned under the row
    /// once the rows have scrolled past the row of views.
    func topRowTable() -> some View {
        modifier(TopRowTable())
    }
}

private struct TopRowScrolls: ViewModifier {
    @Environment(\.topRowSpace) private var space

    func body(content: Content) -> some View {
        content
            .contentMargins(.top, space.restHeight, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { max(0, ($0.contentOffset.y + $0.contentInsets.top).rounded()) } action: { _, new in
                if space.scroll?.offset != new { space.scroll?.offset = new }
            }
            .scrollEdgeEffectHidden(true, for: .top)
    }
}

private struct TopRowTable: ViewModifier {
    @Environment(\.topRowSpace) private var space

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectHidden(true, for: .top)
            .background { TopRowTableProbe(space: space) }
    }
}

/// Reaches the `NSScrollView` behind a table or a list. SwiftUI's `contentMargins` leaves their scroll views alone, so the
/// room for the row of views is the scroll view's own top inset, to which AppKit adds the headings' height. The headings'
/// container is then set at the toolbar's lower edge, or lower while the row of views still shows, and set again whenever
/// the scroll view or AppKit moves it.
private struct TopRowTableProbe: NSViewRepresentable {
    let space: TopRowSpace

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.space = space
        probe.refresh()
    }

    static func dismantleNSView(_ probe: Probe, coordinator: ()) {
        probe.stop()
    }

    final class Probe: NSView {
        var space = TopRowSpace()
        private weak var table: NSTableView?
        private var observers: [any NSObjectProtocol] = []
        private var isPlacing = false

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
            let room = scroll.safeAreaInsets.top + space.restHeight
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
            space.scroll?.offset = 0
        }

        private func place() {
            guard !isPlacing, let table, let scroll = table.enclosingScrollView else { return }
            let clip = scroll.contentView
            let scrolled = max(0, clip.bounds.origin.y + clip.contentInsets.top)
            if let model = space.scroll {
                if model.offset != scrolled { model.offset = scrolled }
                let headings = table.headerView?.frame.height ?? 0
                if model.headingHeight != headings { model.headingHeight = headings }
            }
            // A list has no column headings to pin.
            guard let container = table.headerView?.superview else { return }
            let top = scroll.safeAreaInsets.top + max(0, space.restHeight - scrolled)
            if container.frame.origin.y != top {
                isPlacing = true
                container.frame.origin.y = top
                isPlacing = false
            }
        }
    }
}

// MARK: The window

/// The row's empty space moves the window, and a double click zooms it, as the title bar's would.
private struct TopRowDragArea: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .simultaneousGesture(TapGesture(count: 2).onEnded { Self.titleBarDoubleClick() })
            .accessibilityHidden(true)
    }

    /// What System Settings says a title bar's double click does.
    @MainActor private static func titleBarDoubleClick() {
        guard let window = NSApp.keyWindow else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}

extension View {
    /// Hides the window's own title, which the top row draws, on the window itself: `toolbar(removing: .title)` lets it
    /// return in full screen and under a modal. The window keeps its title for Mission Control and VoiceOver.
    func hidesWindowTitle() -> some View {
        background { WindowTitleHider() }
    }
}

private struct WindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> Hider { Hider() }
    func updateNSView(_ view: Hider, context: Context) { view.hide() }

    final class Hider: NSView {
        private var observer: (any NSObjectProtocol)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            hide()
            // SwiftUI puts the title back as the window enters or leaves full screen and as a modal opens, so it is
            // hidden again at each update of the window. Reading one property is all an update costs.
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification, object: window, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.hide() } }
        }

        func hide() {
            guard let window else { return }
            // The smallest the window goes, as a frame: the toolbar's height is in it.
            if window.minSize.height < 520 { window.minSize = NSSize(width: 760, height: 520) }
            guard window.titleVisibility != .hidden else { return }
            window.titleVisibility = .hidden
        }

        isolated deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

/// Measures the room the window's toolbar takes beside the column this sits behind: how far its leading items and the
/// traffic lights reach into the column, and how far the buttons at its trailing end do. The row keeps clear of that,
/// so it never slides under a button, whatever the buttons and the text size are.
private struct ToolbarRoomProbe: NSViewRepresentable {
    @Binding var room: TopRowRoom
    let signal: AnyHashable

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.report = { new in if room != new { room = new } }
        probe.measureSoon()
    }

    final class Probe: NSView {
        var report: (TopRowRoom) -> Void = { _ in }
        private var observers: [any NSObjectProtocol] = []
        private var watched: [NSView] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return }
            for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.measureSoon() }
                })
            }
            measureSoon()
        }

        override func layout() {
            super.layout()
            measure()
        }

        /// The toolbar moves its items a moment after what changed them, so the room is read now and twice after.
        func measureSoon() {
            measure()
            for delay in [0.05, 0.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.measure() }
            }
        }

        private func measure() {
            guard let window, let toolbar = window.toolbar else { return }
            let column = convert(bounds, to: nil)
            guard column.width > 0 else { return }
            var rects: [NSRect] = []
            var views: [NSView] = []
            for item in toolbar.items {
                guard let view = item.view, view.window === window, !view.isHiddenOrHasHiddenAncestor, view.bounds.width > 1 else { continue }
                rects.append(view.convert(view.bounds, to: nil))
                views.append(view)
            }
            // Items whose view the toolbar does not hand over are found among the title bar's own views.
            if rects.isEmpty, let frame = window.contentView?.superview { Self.collectViewers(in: frame, into: &rects) }
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window.standardWindowButton(kind), !button.isHiddenOrHasHiddenAncestor {
                    rects.append(button.convert(button.bounds, to: nil))
                }
            }
            // Stay told of each item that moves, so the room follows an item that grows, as the search field does.
            if views.map(ObjectIdentifier.init) != watched.map(ObjectIdentifier.init) {
                watched = views
                for view in views {
                    view.postsFrameChangedNotifications = true
                    observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.measure() }
                    })
                }
            }
            let (leading, trailing) = Self.room(of: rects, in: column)
            report(TopRowRoom(leading: leading, trailing: trailing))
        }

        private static func collectViewers(in view: NSView, into rects: inout [NSRect]) {
            for sub in view.subviews {
                if String(describing: type(of: sub)).contains("ToolbarItemViewer") {
                    if !sub.isHiddenOrHasHiddenAncestor, sub.bounds.width > 1 { rects.append(sub.convert(sub.bounds, to: nil)) }
                } else {
                    collectViewers(in: sub, into: &rects)
                }
            }
        }

        /// The items that stand in a row from each end of the column: each begins within a gap of the one before it, as the
        /// toolbar's groups do, and the first begins near the column's edge. Items in the middle are another group's.
        static func room(of rects: [NSRect], in column: NSRect) -> (leading: CGFloat, trailing: CGFloat) {
            let gap: CGFloat = 48
            let inside = rects.filter { $0.maxX > column.minX && $0.minX < column.maxX }
            var leading: CGFloat = 0
            var edge = column.minX
            for rect in inside.sorted(by: { $0.minX < $1.minX }) where rect.minX - edge < gap {
                edge = max(edge, rect.maxX)
                leading = edge - column.minX
            }
            var trailing: CGFloat = 0
            edge = column.maxX
            for rect in inside.sorted(by: { $0.maxX > $1.maxX }) where edge - rect.maxX < gap {
                edge = min(edge, rect.minX)
                trailing = column.maxX - edge
            }
            return (max(0, leading), max(0, trailing))
        }

        isolated deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}
