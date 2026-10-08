import SwiftUI

/// Where an item's details appear when shown, kept for every window.
enum DetailsKey {
    static let style = "detailsStyle"
}

enum DetailsStyle: String {
    /// The system inspector column, which makes room beside the content.
    case sidebar
    /// A card that floats over the content's trailing edge, as the Claude app's session panel does.
    case panel
}

/// How details are shown, offered by the View menu.
struct DetailsStyleOptions: View {
    @AppStorage(DetailsKey.style) private var style = DetailsStyle.sidebar

    var body: some View {
        Picker("Show Details As", systemImage: "info.circle", selection: $style) {
            Text("Sidebar").tag(DetailsStyle.sidebar)
            Text("Floating Panel").tag(DetailsStyle.panel)
        }
        .accessibilityIdentifier("DetailsStyle")
    }
}

/// A floating card over the window's content. It hugs its content's height and scrolls once the window is too
/// short to hold it.
struct DetailsPanel<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 0

    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        GeometryReader { space in
            let available = max(space.size.height - 20, 120)
            content
                .onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, height in contentHeight = height }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: 320, height: contentHeight > 0 ? min(contentHeight, available) : available)
                .background(Color(nsColor: .textBackgroundColor), in: shape)
                .clipShape(shape)
                .overlay { shape.strokeBorder(.separator) }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding([.top, .trailing], 10)
        }
        // Escape puts the panel away, as it does a popover.
        .background {
            Button("Hide Details") { isPresented = false }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
        .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
    }
}
