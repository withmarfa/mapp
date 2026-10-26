import SwiftUI

/// A soft band of glass behind the toolbar, for a page that scrolls under it. The window hides its toolbar's
/// background (`MAPPApp`), and the page's web view is not a SwiftUI scroll view, so the app does not rely on the
/// system drawing a soft edge over the page. This band is the app's own signal that content is under the toolbar:
/// it is absent while nothing is behind the toolbar, and fades in once something is. If the system's edge is ever
/// seen to draw over the page as well, this band is the thing to remove.
struct ToolbarBand: View {
    /// The toolbar's height, which the band covers entirely.
    let toolbarHeight: CGFloat
    let isShown: Bool

    /// How far the band's lower edge fades out below the toolbar, so it ends softly rather than in a line.
    static let fade: CGFloat = 14

    var body: some View {
        Rectangle()
            .fill(.bar)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: toolbarHeight / (toolbarHeight + Self.fade)),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(height: toolbarHeight + Self.fade)
            // With no toolbar over the page, as in full screen while the toolbar is hidden, there is nothing to back.
            .opacity(isShown && toolbarHeight > 0 ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: isShown)
            // Clicks, the window's drag area and the toolbar's buttons all work as if it were not there.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea(.container, edges: .top)
    }
}
