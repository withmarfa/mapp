import SwiftUI

/// The measures of the inspector's property sheet at the default text size, which scale with the interface text.
enum InspectorMetrics {
    static let nameWidth: CGFloat = 92
    static let rowHeight: CGFloat = 28
    static let gap: CGFloat = 8
}

/// A section's heading: small, bold and secondary.
struct InspectorHeading: View {
    let title: LocalizedStringKey
    var topPadding: CGFloat = 14

    var body: some View {
        Text(title)
            .interfaceFont(.subheadline.bold())
            .foregroundStyle(.secondary)
            .padding(.top, topPadding)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A name in the secondary color beside its value, which the caller supplies as a control that looks like plain
/// text until it is hovered or focused. Every row is at least `InspectorMetrics.rowHeight` tall; a value on one
/// line is centered in it, as the wireframe's grid does, and a value that wraps starts at the top with the name
/// level with its first line.
struct InspectorRow<Value: View>: View {
    @Environment(\.interfaceTextSize) private var textSize
    /// Nil leaves the name column empty, for a row that belongs to the one above.
    let name: LocalizedStringKey?
    @ViewBuilder let value: Value

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        InspectorRowLayout(nameWidth: InspectorMetrics.nameWidth * scale, gap: InspectorMetrics.gap * scale,
                           minHeight: InspectorMetrics.rowHeight * scale) {
            Text(name ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityHidden(name == nil)
            value
        }
        .interfaceFont(.callout)
    }
}

/// The two columns of a row: the name at a fixed width and the value in the rest. Built as a layout because the
/// controls a value can be (a menu, a field, plain text) report different baselines and heights, which made rows
/// of the same content differ in height when the name was aligned to them.
struct InspectorRowLayout: Layout {
    let nameWidth: CGFloat
    let gap: CGFloat
    let minHeight: CGFloat

    private func valueWidth(in width: CGFloat?) -> CGFloat? {
        width.map { max(0, $0 - nameWidth - gap) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let name = subviews[0].sizeThatFits(ProposedViewSize(width: nameWidth, height: nil))
        let value = subviews[1].sizeThatFits(ProposedViewSize(width: valueWidth(in: proposal.width), height: nil))
        return CGSize(width: proposal.width ?? nameWidth + gap + value.width, height: max(minHeight, name.height, value.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let valueProposal = ProposedViewSize(width: valueWidth(in: bounds.width), height: nil)
        let name = subviews[0].sizeThatFits(ProposedViewSize(width: nameWidth, height: nil))
        let value = subviews[1].sizeThatFits(valueProposal)
        let valueX = bounds.minX + nameWidth + gap
        let nameY: CGFloat
        let valueY: CGFloat
        if value.height <= minHeight && name.height <= minHeight {
            nameY = bounds.minY + (minHeight - name.height) / 2
            valueY = bounds.minY + (minHeight - value.height) / 2
        } else {
            // The value starts at the top, and the name sits level with its first line.
            valueY = bounds.minY
            let valueBaseline = subviews[1].dimensions(in: valueProposal)[.firstTextBaseline]
            let nameBaseline = subviews[0].dimensions(in: ProposedViewSize(width: nameWidth, height: nil))[.firstTextBaseline]
            nameY = bounds.minY + max(0, valueBaseline - nameBaseline)
        }
        subviews[0].place(at: CGPoint(x: bounds.minX, y: nameY), anchor: .topLeading, proposal: ProposedViewSize(width: nameWidth, height: name.height))
        subviews[1].place(at: CGPoint(x: valueX, y: valueY), anchor: .topLeading, proposal: ProposedViewSize(width: valueProposal.width, height: value.height))
    }
}

private struct InspectorMinimumHeight: ViewModifier {
    @Environment(\.interfaceTextSize) private var textSize

    func body(content: Content) -> some View {
        content.frame(minHeight: InspectorMetrics.rowHeight * InterfaceStyle.scale(for: textSize))
    }
}

private struct InspectorValueStyle: ViewModifier {
    @State private var hovering = false
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovering || isFocused ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -3)
            }
            .onHover { hovering = $0 }
    }
}

extension View {
    /// At least one row tall, for each line of a value that lists several.
    func inspectorMinimumHeight() -> some View { modifier(InspectorMinimumHeight()) }

    /// A value that reads as plain text, and shows the system's subtle fill only while hovered or focused.
    func inspectorValue(isFocused: Bool = false) -> some View {
        modifier(InspectorValueStyle(isFocused: isFocused))
    }
}

/// The text an empty value shows. Text fields and menus share one colour, because a
/// hierarchical style dims twice inside a menu label and a text field's own prompt colour differs from it.
struct InspectorPlaceholder: View {
    static let color = Color(nsColor: .placeholderTextColor)

    let text: LocalizedStringKey

    var body: some View {
        Text(text).foregroundStyle(Self.color)
    }
}

/// The button that ends a section and adds to it: secondary text with a plus, on the same leading edge as the
/// section's names, and a menu of what can be added.
struct InspectorAddMenu<Content: View>: View {
    let title: LocalizedStringKey
    let identifier: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Label(title, systemImage: "plus")
                .interfaceFont(.callout)
                .inspectorMinimumHeight()
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityIdentifier(identifier)
    }
}

/// A hairline between two sections, in place of a box around either.
struct InspectorSectionDivider: View {
    var body: some View {
        Divider().padding(.top, 14)
    }
}
