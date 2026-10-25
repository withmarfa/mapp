import SwiftUI

/// A panel the window shows over everything, as the command palette and quick add are: one shape, material, edge
/// and shadow, and a click anywhere outside puts it away, as it does a menu. The palette sits near the top, as
/// Spotlight does, so its list grows down; a panel the person writes in sits in the middle.
struct FloatingPanel<Content: View>: View {
    enum Placement { case top, center }

    var placement = Placement.top
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: placement == .top ? .top : .center) {
            Color.clear
                .contentShape(.rect)
                .onTapGesture(perform: onDismiss)
            content
                .padding(.top, placement == .top ? 72 : 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }
}

extension View {
    /// The surface a floating panel's content sits on, `width` wide and as tall as the content: the regular Liquid
    /// Glass the system gives popovers and other floating controls that hold text, with its own edge, and a
    /// shadow that lifts it off the window.
    func floatingPanelSurface(width: CGFloat) -> some View {
        frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .glassEffect(.regular, in: .rect(cornerRadius: FloatingPanelMetrics.cornerRadius))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
    }
}

enum FloatingPanelMetrics {
    static let cornerRadius: CGFloat = 20
}
