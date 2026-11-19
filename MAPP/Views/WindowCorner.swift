import SwiftUI

/// The window's bottom-right corner, over the content it belongs to and never over the right sidebar, which the content
/// ends before. It holds how a person views the screen, as glass buttons each on its own; nothing that changes items
/// goes in it. A screen supplies its buttons and, where a button opens one, a card: the card opens above the buttons at
/// their width, or at `cardWidth` where the card is wider than they are, right-aligned, solid rather than glass, and
/// the buttons stay. With no buttons the corner draws nothing.
///
/// A toast rises from the foot of the same content, so the corner lifts above it while one shows.
struct WindowCorner<Buttons: View, Card: View>: View {
    var isCardOpen = false
    var cardWidth: CGFloat?
    @ViewBuilder var buttons: Buttons
    @ViewBuilder var card: Card

    @State private var buttonsWidth: CGFloat = 0
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Environment(\.interfaceTextSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The gap between the corner and the content's edges, and between its buttons and its card.
    static var inset: CGFloat { 16 }

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        // The toast's own height and the space under it (`ToastHost`), and a little between.
        let lift = details?.toasts.current == nil ? 0 : 22 + 44 * scale + 10 - Self.inset
        VStack(alignment: .trailing, spacing: 8) {
            if isCardOpen {
                card
                    .frame(width: cardWidth ?? (buttonsWidth > 0 ? buttonsWidth : nil))
                    .background(.background, in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                    .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
            }
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 8) { buttons }
            }
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { buttonsWidth = $0 }
        }
        .padding([.trailing, .bottom], Self.inset)
        .padding(.bottom, lift)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isCardOpen)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: lift)
    }
}

extension WindowCorner where Card == EmptyView {
    /// A corner with buttons only.
    init(@ViewBuilder buttons: () -> Buttons) {
        self.init(isCardOpen: false, cardWidth: nil, buttons: buttons, card: { EmptyView() })
    }
}

/// A button in the corner: a glass capsule, as the toolbar's buttons are. One that is on is gray, never the accent
/// color. An icon alone is as wide as it is tall.
struct CornerButtonStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        CornerButtonLabel(label: configuration.label, isOn: isOn, isPressed: configuration.isPressed)
    }
}

private struct CornerButtonLabel<Label: View>: View {
    let label: Label
    let isOn: Bool
    let isPressed: Bool
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let height = CornerMetrics.height * InterfaceStyle.scale(for: textSize)
        label
            .font(.system(size: 13 * InterfaceStyle.scale(for: textSize)))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minWidth: height, minHeight: height)
            .background { if isOn || isPressed { Capsule().fill(.primary.opacity(isOn ? 0.14 : 0.08)).padding(3) } }
            .contentShape(.capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

enum CornerMetrics {
    /// The height of a button at the default interface text size.
    static let height: CGFloat = 32

    /// How far a scroll view's content ends above its foot, so its last line scrolls clear of the buttons: the buttons'
    /// height with the gap around them (`WindowCorner.inset`) above and below.
    static func clearance(scale: CGFloat) -> CGFloat { height * scale + WindowCorner<EmptyView, EmptyView>.inset * 2 }
}

/// Two or more related icon buttons in one glass capsule with no divider, such as back and forward. Each segment fills
/// softly under the pointer.
struct CornerButtonGroup<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let height = CornerMetrics.height * InterfaceStyle.scale(for: textSize)
        HStack(spacing: 0) { content }
            .buttonStyle(CornerSegmentStyle())
            .padding(.horizontal, 3)
            .frame(height: height)
            .glassEffect(.regular, in: .capsule)
    }
}

private struct CornerSegmentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Segment(configuration: configuration)
    }

    private struct Segment: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.interfaceTextSize) private var textSize

        var body: some View {
            let scale = InterfaceStyle.scale(for: textSize)
            configuration.label
                .font(.system(size: 13 * scale, weight: .medium))
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .frame(width: 34 * scale)
                .frame(maxHeight: .infinity)
                .background(.primary.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.1 : 0), in: .capsule)
                .padding(.vertical, 3)
                .contentShape(.capsule)
                .onHover { isHovered = $0 }
        }
    }
}

/// A corner button that opens a menu, named by its current choice, such as the gallery's card size. The chevron is
/// drawn here, so the system's own indicator stays hidden.
struct CornerMenu<Content: View>: View {
    /// Already in the person's language.
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: title)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(CornerButtonStyle())
        .fixedSize()
    }
}
