import SwiftUI

/// A band of blurred material over the toolbar, ended by a hairline, for content that scrolls under it, in the
/// manner of the system's hard scroll edge effect. The window hides its toolbar's background (`MAPPApp`), the
/// page's web view is not a SwiftUI scroll view, and WebKit's own scroll edge is not public API, so the app draws
/// the band itself: it is absent while nothing is behind the toolbar and appears once something is. The list
/// always draws it. A note's or item's page draws it unless Show Toolbar Background When Scrolling is off
/// (`InterfaceKey.showsPageToolbarBackground`, read by `NotePage`).
struct ToolbarBand: View {
    /// The toolbar's height, which the band covers entirely and ends at, with no fade below it.
    let toolbarHeight: CGFloat
    let isShown: Bool

    /// How much of the blur shows, so the content behind reads only as a faint ghost.
    static let strength: Double = 0.9

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(.bar)
            .opacity(Self.strength)
            .overlay(alignment: .bottom) {
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
            .ignoresSafeArea(.container, edges: .top)
    }
}

extension View {
    /// Gives a list or other scroll view the same toolbar edge as the page: a `ToolbarBand` over the toolbar once
    /// the content has scrolled beneath it. The system's own edge for the scroll view is hidden, so only one draws.
    func bandsToolbar() -> some View {
        modifier(BandsToolbar())
    }
}

private struct BandsToolbar: ViewModifier {
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
                    ToolbarBand(toolbarHeight: proxy.safeAreaInsets.top, isShown: isUnderToolbar)
                }
            }
    }
}
