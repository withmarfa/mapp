import SwiftUI

/// A panel the window shows over everything near its top, as the command palette and quick add are: one shape,
/// material, edge and shadow, and a click anywhere outside puts it away, as it does a menu.
struct FloatingPanel<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(.rect)
                .onTapGesture(perform: onDismiss)
            content
                .padding(.top, 72)
                .padding(.horizontal, 16)
        }
    }
}

extension View {
    /// The surface a floating panel's content sits on, `width` wide and as tall as the content.
    func floatingPanelSurface(width: CGFloat) -> some View {
        frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: .rect(cornerRadius: FloatingPanelMetrics.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: FloatingPanelMetrics.cornerRadius).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
    }
}

enum FloatingPanelMetrics {
    static let cornerRadius: CGFloat = 12
}
