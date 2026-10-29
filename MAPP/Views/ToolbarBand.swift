import SwiftUI

/// A band of blurred material over the toolbar, ended by a hairline, for content that scrolls under it, in the
/// manner of the system's hard scroll edge effect. The window hides its toolbar's background (`MAPPApp`), the
/// page's web view is not a SwiftUI scroll view, and WebKit's own scroll edge is not public API, so the page, and
/// only the page, draws the band itself: it is absent while nothing is behind the toolbar and appears once something
/// is, unless Show Toolbar Background When Scrolling is off (`InterfaceKey.showsPageToolbarBackground`, read by
/// `NotePage`). Every SwiftUI scroll view uses the system's edge instead (`toolbarScrollEdge`).
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
    /// Gives a scroll view the system's hard scroll edge effect under the toolbar: nothing while nothing is beneath
    /// it, and the blurred edge once content scrolls under. Every layout that scrolls in SwiftUI uses it, so they
    /// share one edge. Show Toolbar Background When Scrolling (`InterfaceKey.showsPageToolbarBackground`) turns it off.
    func toolbarScrollEdge() -> some View {
        modifier(ToolbarScrollEdge())
    }
}

private struct ToolbarScrollEdge: ViewModifier {
    @AppStorage(InterfaceKey.showsPageToolbarBackground) private var showsBackground = true

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.hard, for: .top)
            .scrollEdgeEffectHidden(!showsBackground, for: .top)
    }
}
