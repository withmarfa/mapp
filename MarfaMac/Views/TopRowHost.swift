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

    /// Forgets what a layout that has gone left, so the next one starts at its top.
    func reset() {
        if offset != 0 { offset = 0 }
        if headingHeight != 0 { headingHeight = 0 }
    }
}

/// What a list needs to know of the top row above it: the room the row of views takes at rest, which the list leaves
/// at its top, and where to say how far it has scrolled.
struct TopRowSpace {
    var scroll: TopRowScroll?
    var restHeight: CGFloat = 0
    /// The height of the title's line: the toolbar's, and never less, so the line stands in full screen with the toolbar
    /// hidden too.
    var lineHeight: CGFloat = TopRowMetrics.lineHeight
    /// How much of the line the column's own top inset does not already cover, which is all of it while the toolbar is
    /// hidden.
    var uncovered: CGFloat = 0
    /// Where the title stands from the column's edge, past the traffic lights, the sidebar's button and Back and Forward
    /// where they stand over the column, which a table's first column follows.
    var titleLead: CGFloat = TopRowMetrics.lead
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
    /// The toolbar's height as the column's top inset says, which is zero while full screen hides the toolbar.
    @State private var insetTop: CGFloat = TopRowMetrics.lineHeight
    @State private var room = TopRowRoom()
    /// How far full screen has slid the toolbar down to show the menu bar.
    @State private var reveal: CGFloat = 0
    let scroll: TopRowScroll?
    /// The room the row of views takes at rest, or zero where there is none.
    let restHeight: CGFloat
    /// Whether the row draws the band the rows scroll under. A page draws its own.
    let bands: Bool
    /// What changes the toolbar's items, so the room is measured again.
    let signal: AnyHashable
    /// How much of the line's lower edge does not move the window, where a page's first line stands under it.
    let dragClearance: CGFloat
    /// Where the title stands for the room the toolbar's items take, which the line pads it to and the column reads
    /// (`TopRowSpace.titleLead`).
    let titleLead: (TopRowRoom) -> CGFloat
    /// The line, told where the title stands and whether the rows have scrolled past the row of views at rest.
    let line: (_ lead: CGFloat, _ room: TopRowRoom, _ isAway: Bool) -> Line
    let rest: (_ lead: CGFloat) -> Rest

    init(
        scroll: TopRowScroll?, restHeight: CGFloat, bands: Bool, signal: AnyHashable, dragClearance: CGFloat = 0,
        titleLead: @escaping (TopRowRoom) -> CGFloat = { $0.titleLead() },
        @ViewBuilder line: @escaping (_ lead: CGFloat, _ room: TopRowRoom, _ isAway: Bool) -> Line,
        @ViewBuilder rest: @escaping (_ lead: CGFloat) -> Rest
    ) {
        self.scroll = scroll
        self.restHeight = restHeight
        self.bands = bands
        self.signal = signal
        self.dragClearance = dragClearance
        self.titleLead = titleLead
        self.line = line
        self.rest = rest
    }

    func body(content: Content) -> some View {
        let lineHeight = max(insetTop, TopRowMetrics.lineHeight)
        let lead = titleLead(room)
        content
            .environment(
                \.topRowSpace,
                TopRowSpace(scroll: scroll, restHeight: restHeight, lineHeight: lineHeight, uncovered: lineHeight - insetTop, titleLead: lead)
            )
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { insetTop = $0 }
            .background { ToolbarRoomProbe(room: $room, signal: signal) }
            .background { ToolbarRevealProbe(reveal: $reveal) }
            .overlay(alignment: .top) {
                TopRowStack(
                    scroll: scroll, restHeight: restHeight, height: lineHeight, bands: bands && showsBackground, dragClearance: dragClearance, room: room,
                    reveal: reveal, line: { line(lead, $0, $1) }, rest: { rest(lead) })
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
    let dragClearance: CGFloat
    let room: TopRowRoom
    /// How far the toolbar has slid down to show the menu bar, which the line follows.
    let reveal: CGFloat
    let line: (TopRowRoom, Bool) -> Line
    let rest: () -> Rest

    var body: some View {
        let offset = scroll?.offset ?? 0
        // Slid down with the toolbar, the line takes the room of the row of views, whose views then stand beside the title.
        let isAway = restHeight == 0 || offset >= restHeight - 0.5 || reveal > 0
        let headings = scroll?.headingHeight ?? 0
        // The first row is as far below the toolbar as the row of views and the headings are tall.
        let isUnder = bands && offset > restHeight + headings + 0.5
        ZStack(alignment: .top) {
            ToolbarBand(toolbarHeight: height, isShown: isUnder, isBacked: true)
            VStack(spacing: 0) {
                line(room, isAway)
                    .frame(height: height)
                    .background { TopRowDragArea().padding(.bottom, dragClearance) }
                if restHeight > 0, !isAway {
                    rest()
                        .frame(height: restHeight, alignment: .top)
                        .offset(y: -min(offset, restHeight))
                        .frame(height: restHeight, alignment: .top)
                        .clipped()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .offset(y: reveal)
    }
}

extension TopRowRoom {
    /// The title's inset at the column's start: `base`, or further where the traffic lights, the sidebar's button and Back
    /// and Forward stand over it.
    func titleLead(base: CGFloat = TopRowMetrics.lead) -> CGFloat { max(base, leading > 0 ? leading + TopRowMetrics.leadingClearance : 0) }
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
            .contentMargins(.top, space.restHeight + space.uncovered, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { max(0, ($0.contentOffset.y + $0.contentInsets.top).rounded()) } action: { _, new in
                if space.scroll?.offset != new { space.scroll?.offset = new }
            }
            .scrollEdgeEffectHidden(true, for: .top)
            // A layout that goes leaves its scroll behind, which the next one does not share.
            .onDisappear { space.scroll?.reset() }
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
/// room for the row of views is added to the scroll view's own safe area, from which AppKit sets its insets with the
/// toolbar's height, the sidebar over the column and the headings' height. The headings' container is then set at the
/// title line's lower edge, or lower while the row of views still shows, and set again whenever the scroll view or AppKit
/// moves it. The line's height is the top row's (`TopRowSpace`), which stands also while full screen hides the toolbar.
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
            // AppKit keeps the insets from the safe area, so they follow a sidebar shown or hidden over the column at once.
            // What the title bar and toolbar already cover, none while full screen hides them: measured from the window,
            // never from the safe area, which holds what was added here until AppKit next lays out.
            guard let window else { return }
            let top = scroll.convert(scroll.bounds, to: nil).maxY
            let covered = max(0, top - window.contentLayoutRect.maxY)
            let extra = max(0, space.lineHeight + space.restHeight - covered)
            if scroll.additionalSafeAreaInsets.top != extra {
                var added = scroll.additionalSafeAreaInsets
                added.top = extra
                scroll.additionalSafeAreaInsets = added
            }
            place()
        }

        private func follow(_ table: NSTableView, in scroll: NSScrollView) {
            stop()
            self.table = table
            // The room the toolbar leaves is read from the scroll view's frame and the window's, which a resize sets after
            // this view's layout: the insets are set again once each has its new size.
            scroll.postsFrameChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: scroll, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
            if let window = scroll.window {
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main
                ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
            }
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
            space.scroll?.reset()
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
            let top = space.lineHeight + max(0, space.restHeight - scrolled)
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
    @State private var window: NSWindow?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .simultaneousGesture(TapGesture(count: 2).onEnded { Self.titleBarDoubleClick(window) })
            // As a title bar does, the first click of a window not in front already drags or zooms it.
            .allowsWindowActivationEvents()
            .background { WindowReader(window: $window) }
            .accessibilityHidden(true)
    }

    /// What System Settings says a title bar's double click does, for the window this row is in.
    @MainActor private static func titleBarDoubleClick(_ window: NSWindow?) {
        guard let window else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}

/// Reads the window a view is in.
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> Reader { Reader() }
    func updateNSView(_ view: Reader, context: Context) {
        view.report = { if window !== $0 { window = $0 } }
        DispatchQueue.main.async { [weak view] in view?.report(view?.window) }
    }

    final class Reader: NSView {
        var report: (NSWindow?) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.report(self?.window) }
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
        private var visibility: NSKeyValueObservation?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            visibility = nil
            guard let window else { return }
            hide()
            // SwiftUI puts the title back as the place changes, as the window enters or leaves full screen and as a
            // modal opens, sometimes after the last event, when no update of the window follows. So it is hidden again
            // the moment it is shown, and at each update of the window for a change no observer is told of.
            visibility = window.observe(\.titleVisibility) { [weak self] _, _ in MainActor.assumeIsolated { self?.hide() } }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification, object: window, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.hide() } }
        }

        func hide() {
            guard let window, window.titleVisibility != .hidden else { return }
            window.titleVisibility = .hidden
        }

        isolated deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

/// Reports how far full screen has slid the toolbar down to show the menu bar. The content's safe area does not change
/// as it does: only the toolbar's own window moves, so the row drawn under the toolbar reads that window's frame. That
/// window also lays an opaque layer of its own (`NSOpaqueBackstop`) over the column's top edge, from the sidebar's edge to
/// the panel's width while the panel is open, which hides the first letters of the title: the probe hides it.
private struct ToolbarRevealProbe: NSViewRepresentable {
    @Binding var reveal: CGFloat

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.report = { new in if reveal != new { reveal = new } }
    }

    final class Probe: NSView {
        var report: (CGFloat) -> Void = { _ in }
        private var observers: [any NSObjectProtocol] = []
        private var barObservers: [any NSObjectProtocol] = []
        private weak var backstop: CALayer?
        private var backstopWatch: NSKeyValueObservation?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return followBar() }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.followBar() }
                })
            }
            followBar()
        }

        /// In full screen the toolbar and the window's buttons stand in a window of their own, which slides.
        private var bar: NSWindow? {
            guard let window, window.styleMask.contains(.fullScreen), let bar = window.standardWindowButton(.closeButton)?.window,
                  bar !== window else { return nil }
            return bar
        }

        private func followBar() {
            barObservers.forEach { NotificationCenter.default.removeObserver($0) }
            barObservers = []
            if let bar {
                hideBackstop(of: bar)
                // The window lays the layer out again with the panel and the first time it shows, after the last event.
                barObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: bar, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if let bar = self?.bar { self?.hideBackstop(of: bar) } }
                })
                barObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: bar, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.measure() }
                })
            }
            measure()
        }

        /// Hides the backstop and keeps it hidden: the window shows it again each time it lays out, with the panel opening
        /// or closing among those.
        private func hideBackstop(of bar: NSWindow) {
            guard let layer = bar.contentView?.layer?.sublayers?.first(where: { $0.name == "NSOpaqueBackstop" }) else { return }
            if layer !== backstop {
                backstop = layer
                backstopWatch = layer.observe(\.isHidden) { layer, _ in
                    if !layer.isHidden { layer.isHidden = true }
                }
            }
            layer.isHidden = true
        }

        private func measure() {
            guard let window, let bar else { return report(0) }
            hideBackstop(of: bar)
            // Hidden above the screen it is not over the row, which then stays.
            report(max(0, window.frame.maxY - bar.frame.maxY))
        }

        isolated deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            barObservers.forEach { NotificationCenter.default.removeObserver($0) }
        }
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
        /// The window's own changes, and the frame changes of each toolbar item watched (`watched`).
        private var observers: [any NSObjectProtocol] = []
        private var itemObservers: [any NSObjectProtocol] = []
        private var watched: [NSView] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            unwatchItems()
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
                unwatchItems()
                watched = views
                for view in views {
                    view.postsFrameChangedNotifications = true
                    itemObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.measure() }
                    })
                }
            }
            let (leading, trailing) = Self.room(of: rects, in: column)
            report(TopRowRoom(leading: leading, trailing: trailing))
        }

        private func unwatchItems() {
            itemObservers.forEach { NotificationCenter.default.removeObserver($0) }
            itemObservers = []
            watched = []
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
        /// toolbar's groups do, and the first begins near the column's edge. Items in the middle are another group's. The
        /// gap is wider than the space between the items of one group and narrower than the one between the leading group
        /// and the list's own buttons.
        static func room(of rects: [NSRect], in column: NSRect) -> (leading: CGFloat, trailing: CGFloat) {
            let gap: CGFloat = 24
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

        isolated deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            itemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
