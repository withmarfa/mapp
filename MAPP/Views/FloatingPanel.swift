import SwiftUI

/// A panel the window shows over everything, as the command palette, the search palette and quick add are: one
/// shape, material, edge and shadow, and a click anywhere outside puts it away, as it does a menu. Every panel
/// starts at the same height, its top about a fifth of the way down the window and centred over it, so what
/// grows grows downward.
struct FloatingPanel<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { window in
            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: onDismiss)
                content
                    .padding(.top, window.size.height * FloatingPanelMetrics.topFraction)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
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
    /// How far down the window a panel's top sits, as a fraction of its height.
    static let topFraction: CGFloat = 0.17
}
