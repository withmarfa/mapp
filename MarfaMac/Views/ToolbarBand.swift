import SwiftUI

/// A band of blurred material over the toolbar, ended by a hairline, for content that scrolls under it, in the
/// manner of the system's hard scroll edge effect. The window hides its toolbar's background (`MarfaMacApp`), so the
/// system's own edge never draws for a view in it; the app draws the band itself. It is absent while nothing is
/// behind the toolbar and appears once something is. The page draws it from the web view's report
/// (`EditorController.isContentUnderToolbar`), and the list, gallery, board and timeline from the top row's scroll
/// (`TopRowFrame`).
/// Show Toolbar Background When Scrolling (`InterfaceKey.showsPageToolbarBackground`) turns it off in all of them.
/// The sidebar's foot draws the same band mirrored (`edge: .bottom`).
struct ToolbarBand: View {
    /// The height the band covers entirely and ends at, with no fade beyond it: the toolbar's, or the sidebar foot's.
    let toolbarHeight: CGFloat
    let isShown: Bool
    /// The edge the band sits on. The hairline runs along the side facing the content.
    var edge: VerticalEdge = .top
    /// Whether the hairline shows. The foot draws none.
    var showsLine = true
    /// How much of the blur shows.
    var strength = Self.strength
    /// Whether the material is backed by the content's own ground. Over AppKit's table and list the material blurs
    /// nothing, so rows would read sharp through it; backed, they read only as the faint ghost `strength` leaves.
    var isBacked = false

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
            .background { if isBacked { Color(nsColor: .controlBackgroundColor) } }
            .opacity(strength)
            .overlay(alignment: edge == .top ? .bottom : .top) {
                // One physical pixel, whatever the display's scale.
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1 / displayScale)
                    .opacity(showsLine ? 1 : 0)
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
    /// Gives a sidebar list a foot that draws a translucent band, as the toolbar's does mirrored and without its line,
    /// while rows pass under it (the content's end lies below the top of the foot). Otherwise the foot sits on the
    /// plain sidebar, with no fill. The pointer changes nothing: the foot looks the same hovered or not. The list's
    /// own background is not content, so it never counts.
    ///
    /// The foot's measures are read from `memory` and written back to it, where a list is mounted afresh with the same
    /// foot, so the first frame already draws the band or not as the last one did.
    func bandsFoot<Foot: View>(memory: ColumnMemory? = nil, @ViewBuilder _ foot: () -> Foot) -> some View {
        modifier(BandsFoot(foot: foot(), memory: memory))
    }
}

private struct BandsFoot<Foot: View>: ViewModifier {
    let foot: Foot
    let memory: ColumnMemory?
    @State private var footHeight: CGFloat
    @State private var hiddenBelow: CGFloat

    init(foot: Foot, memory: ColumnMemory?) {
        self.foot = foot
        self.memory = memory
        _footHeight = State(initialValue: memory?.footHeight ?? 0)
        _hiddenBelow = State(initialValue: memory?.hiddenBelow ?? 0)
    }

    /// How much of the blur shows while rows pass under the foot.
    private static var underFootStrength: Double { 0.6 }

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
                        ToolbarBand(
                            toolbarHeight: footHeight, isShown: isUnderFoot, edge: .bottom,
                            showsLine: false, strength: Self.underFootStrength)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        footHeight = $0
                        memory?.footHeight = $0
                    }
            }
    }
}
