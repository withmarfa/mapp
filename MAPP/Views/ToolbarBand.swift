import SwiftUI

/// A band of blurred material over the toolbar, ended by a hairline, for content that scrolls under it, in the
/// manner of the system's hard scroll edge effect. The window hides its toolbar's background (`MAPPApp`), so the
/// system's own edge never draws for a view in it; the app draws the band itself. It is absent while nothing is
/// behind the toolbar and appears once something is. The page draws it from the web view's report
/// (`EditorController.isContentUnderToolbar`), and the list, gallery, board and timeline through `bandsToolbar()`.
/// Show Toolbar Background When Scrolling (`InterfaceKey.showsPageToolbarBackground`) turns it off in all of them.
/// The sidebar's foot draws the same band mirrored (`edge: .bottom`).
struct ToolbarBand: View {
    /// The height the band covers entirely and ends at, with no fade beyond it: the toolbar's, or the sidebar foot's.
    let toolbarHeight: CGFloat
    let isShown: Bool
    /// The edge the band sits on. The hairline runs along the side facing the content.
    var edge: VerticalEdge = .top

    /// How much of the blur shows, so the content behind reads only as a faint ghost.
    static let strength: Double = 0.9

    /// Whether rows pass under a foot of `footHeight` on the bottom edge, given how far the content's end lies below
    /// the scroll view's bottom edge (negative while it ends above it).
    static func isUnderFoot(hiddenBelow: CGFloat, footHeight: CGFloat) -> Bool {
        footHeight > 0 && hiddenBelow + footHeight > 0.5
    }

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(.bar)
            .opacity(Self.strength)
            .overlay(alignment: edge == .top ? .bottom : .top) {
                // One physical pixel, whatever the display's scale.
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1 / displayScale)
            }
            .frame(height: toolbarHeight)
            // With no toolbar over the page, as in full screen while the toolbar is hidden, there is nothing to back.
            .opacity(isShown && toolbarHeight > 0 ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: isShown)
            // Clicks, the window's drag area and the toolbar's buttons all work as if it were not there.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea(.container, edges: edge == .top ? .top : .bottom)
    }
}

extension View {
    /// Gives a list or other scroll view the same toolbar edge as the page: a `ToolbarBand` over the toolbar once
    /// the content has scrolled beneath it. The system's own edge for the scroll view is hidden, so only one draws.
    /// Show Toolbar Background When Scrolling (`InterfaceKey.showsPageToolbarBackground`) turns the band off.
    /// Attach it to the scroll view itself, so the scroll geometry it reads is that view's.
    func bandsToolbar() -> some View {
        modifier(BandsToolbar())
    }

    /// Gives a sidebar list a foot that draws as the toolbar's band does, mirrored, only while rows pass under it:
    /// the content's end lies below the top of the foot. Otherwise the foot sits on
    /// the plain sidebar, with no fill and no line. The list's own background is not content, so it never counts.
    ///
    /// The foot's measures are read from `memory` and written back to it, where a list is mounted afresh with the same
    /// foot, so the first frame already draws the band or not as the last one did.
    func bandsFoot<Foot: View>(memory: SidebarMemory? = nil, @ViewBuilder _ foot: () -> Foot) -> some View {
        modifier(BandsFoot(foot: foot(), memory: memory))
    }
}

private struct BandsToolbar: ViewModifier {
    @AppStorage(InterfaceKey.showsPageToolbarBackground) private var showsBackground = true
    @State private var isUnderToolbar = false

    func body(content: Content) -> some View {
        content
            // At rest the content starts exactly below the toolbar, which the scroll geometry reports as an inset.
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0.5 } action: { _, new in
                isUnderToolbar = new
            }
            .scrollEdgeEffectHidden(true, for: .top)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    ToolbarBand(toolbarHeight: proxy.safeAreaInsets.top, isShown: showsBackground && isUnderToolbar)
                }
            }
    }
}

private struct BandsFoot<Foot: View>: ViewModifier {
    let foot: Foot
    let memory: SidebarMemory?
    @State private var footHeight: CGFloat
    @State private var hiddenBelow: CGFloat

    init(foot: Foot, memory: SidebarMemory?) {
        self.foot = foot
        self.memory = memory
        _footHeight = State(initialValue: memory?.footHeight ?? 0)
        _hiddenBelow = State(initialValue: memory?.hiddenBelow ?? 0)
    }

    /// Rows are under the foot once the content's end lies below the top of the foot, that is, when it reaches more
    /// than the foot's height above the scroll view's bottom edge. Content that ends just above the foot is not under it.
    private var isUnderFoot: Bool { ToolbarBand.isUnderFoot(hiddenBelow: hiddenBelow, footHeight: footHeight) }

    func body(content: Content) -> some View {
        content
            // The content's end less the scroll view's bottom edge, which the foot covers. Whole points, so the sidebar is not redrawn for every pixel of a scroll.
            .onScrollGeometryChange(for: CGFloat.self) { ($0.contentSize.height - $0.bounds.maxY).rounded() } action: { _, new in
                hiddenBelow = new
                memory?.hiddenBelow = new
            }
            .scrollEdgeEffectHidden(true, for: .bottom)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                foot
                    .background(alignment: .bottom) {
                        ToolbarBand(toolbarHeight: footHeight, isShown: isUnderFoot, edge: .bottom)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        footHeight = $0
                        memory?.footHeight = $0
                    }
            }
    }
}
