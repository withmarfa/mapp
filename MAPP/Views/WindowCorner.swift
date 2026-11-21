import SwiftUI

/// The window's bottom-right corner, over the content it belongs to and never over the right sidebar, which the content
/// ends before. It holds how a person views the screen, as glass buttons each on its own; nothing that changes items
/// goes in it. A screen supplies its buttons and, where a button opens one, a card, and the buttons stay. The card opens
/// above the buttons at their width, or at `cardWidth` where the card is wider than they are, right-aligned, solid
/// rather than glass; or, placed `.centeredAtFoot`, as a bar on the same line as the buttons, centered on the content and
/// kept clear of them, or above them when it is too wide to sit beside them (`FootBarLayout`); the bar draws its own
/// glass. With no buttons the corner draws nothing.
///
/// A toast rises from the foot of the same content, so the corner lifts above it while one shows.
struct WindowCorner<Buttons: View, Card: View>: View {
    /// Where an open card sits.
    enum CardPlacement {
        /// Above the buttons, solid.
        case aboveButtons
        /// Along the foot of the content, centered on it and clear of the buttons.
        case centeredAtFoot
    }

    var isCardOpen = false
    var cardWidth: CGFloat?
    var cardPlacement = CardPlacement.aboveButtons
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
            if isCardOpen && cardPlacement == .aboveButtons {
                card
                    .frame(width: cardWidth ?? (buttonsWidth > 0 ? buttonsWidth : nil))
                    // The corner fills the content's height, which a card's flexible parts (a divider, a spacer, an
                    // empty cell) would take; the card keeps its content's own height.
                    .fixedSize(horizontal: false, vertical: true)
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
            // The arrow, even over a web view, which would draw its own pointer under the buttons.
            .pointerStyle(.default)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { buttonsWidth = $0 }
        }
        .padding([.trailing, .bottom], Self.inset)
        .padding(.bottom, lift)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .overlay {
            if isCardOpen && cardPlacement == .centeredAtFoot {
                FootBarLayout(leading: Self.inset, trailing: buttonsWidth + Self.inset * 2, raise: CornerMetrics.height * scale + Self.inset) { card.pointerStyle(.default) }
                    .padding(.bottom, Self.inset + lift)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isCardOpen)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: lift)
    }
}

/// Puts its one child along the foot, as wide as it asks for and no wider than the room between `leading` and `trailing`
/// from the edges, centered on the whole width where that room allows and moved aside where it does not.
private struct FootBarLayout: Layout {
    var leading: CGFloat
    var trailing: CGFloat
    /// How far the bar lifts when it cannot sit beside the buttons: their height and the gap above them.
    var raise: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? ideal.width, height: proposal.height ?? ideal.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bar = subviews.first else { return }
        let ideal = bar.sizeThatFits(.unspecified).width
        let beside = max(0, bounds.width - leading - trailing)
        // A bar too wide to sit beside the buttons rises above them while the column has room for it, and only then scrolls.
        let lifted = ideal > beside
        let room = lifted ? max(0, bounds.width - leading * 2) : beside
        let width = min(ideal, room)
        let end = lifted ? bounds.maxX - leading : bounds.maxX - trailing
        let x = min(max(bounds.midX - width / 2, bounds.minX + leading), end - width)
        bar.place(
            at: CGPoint(x: x, y: bounds.maxY - (lifted ? raise : 0)), anchor: .bottomLeading,
            proposal: ProposedViewSize(width: width, height: nil))
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
            .background { if isPressed && !isOn { Capsule().fill(.primary.opacity(0.08)).padding(3) } }
            .contentShape(.capsule)
            .glassEffect(isOn ? .regular.tint(CornerMetrics.onTint).interactive() : .regular.interactive(), in: .capsule)
    }
}

enum CornerMetrics {
    /// What a button or a chosen segment that is on is tinted with: gray, never the accent color.
    static let onTint = Color.gray.opacity(0.45)

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
                .frame(minWidth: 34 * scale)
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

extension View {
    /// A corner's choice of a few as the system's segmented control, its chosen segment gray rather than the accent
    /// color, and as wide as its labels.
    func cornerSegmented() -> some View {
        pickerStyle(.segmented)
            .labelsHidden()
            .tint(.gray)
            .fixedSize()
    }
}
