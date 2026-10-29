import SwiftUI

/// The measures of the inspector's property sheet at the default text size, which scale with the interface text.
enum InspectorMetrics {
    static let nameWidth: CGFloat = 96
    static let rowHeight: CGFloat = 28
    static let gap: CGFloat = 8
    /// The space between two sections, in place of a rule.
    static let sectionGap: CGFloat = 24
    /// The space between a section's heading and what it holds.
    static let headingGap: CGFloat = 8
    static let chipRadius: CGFloat = 7
    /// What a chip adds to the width of its text: its padding on both sides.
    static let chipPadding: CGFloat = 16
}

/// A section's heading: the system's headline in the primary color, with space above it instead of a rule.
struct InspectorHeading: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .interfaceFont(.headline)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A section that folds: its heading with the disclosure at its end, and a count where the section lists things.
struct InspectorFoldHeading: View {
    @Environment(\.interfaceTextSize) private var textSize
    let title: LocalizedStringKey
    var count: Int?
    /// A quieter heading, for a section nobody comes to read first.
    var isQuiet = false
    @Binding var isOpen: Bool
    let identifier: String

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if let count {
                    Text(count, format: .number).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10 * InterfaceStyle.scale(for: textSize), weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .interfaceFont(isQuiet ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(isQuiet ? .secondary : .primary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
        .accessibilityIdentifier(identifier)
    }
}

/// What a value would measure on one line, so a row can tell whether it fits beside its name. A value that is a
/// chip adds the chip's padding, and one with a mark ahead of its text adds the mark.
struct InspectorFit {
    var text: String
    var extra: CGFloat = 0
}

/// A name in the secondary color beside its value, or above it when the value will not fit beside. The name is
/// always one line, cut to the name column with the full name as its help, so one row never runs into the next.
/// Every row is at least `InspectorMetrics.rowHeight` tall; a value on one line is centered in it.
struct InspectorRow<Value: View>: View {
    @Environment(\.interfaceTextSize) private var textSize
    let name: Text
    let help: String
    var fit: InspectorFit?
    @ViewBuilder let value: Value

    init(name: LocalizedStringResource, fit: InspectorFit? = nil, @ViewBuilder value: () -> Value) {
        self.name = Text(name)
        help = String(localized: name)
        self.fit = fit
        self.value = value()
    }

    /// A name that comes from Marfa, shown as it is.
    init(verbatimName: String, fit: InspectorFit? = nil, @ViewBuilder value: () -> Value) {
        name = Text(verbatim: verbatimName)
        help = verbatimName
        self.fit = fit
        self.value = value()
    }

    /// A field's label, which the app may have a translation for.
    init(fieldLabel: String, fit: InspectorFit? = nil, @ViewBuilder value: () -> Value) {
        name = Text(LocalizedStringKey(fieldLabel))
        help = fieldLabel
        self.fit = fit
        self.value = value()
    }

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        InspectorRowLayout(nameWidth: InspectorMetrics.nameWidth * scale, gap: InspectorMetrics.gap * scale,
                           minHeight: InspectorMetrics.rowHeight * scale) {
            name
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(help)
            value
            // The value's text again, hidden, to measure; a control's own width says little about its text.
            Text(verbatim: fit?.text ?? "")
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, (fit?.extra ?? 0) / 2)
                .hidden()
                .accessibilityHidden(true)
        }
        .interfaceFont(.callout)
    }
}

/// The columns of a row: the name at a fixed width and the value in the rest, or the name with the value under it
/// at the full width when the third subview, which measures the value on one line, is wider than the value column.
/// Built as a layout because the controls a value can be (a menu, a field, plain text) report different baselines
/// and heights, and because the choice between the two shapes must not recreate the value, which may hold what the
/// person is typing.
struct InspectorRowLayout: Layout {
    let nameWidth: CGFloat
    let gap: CGFloat
    let minHeight: CGFloat
    /// The space between a name and the value under it.
    private var stackGap: CGFloat { 2 }

    private func isStacked(width: CGFloat, subviews: Subviews) -> Bool {
        let needed = subviews[2].sizeThatFits(.unspecified).width
        return needed > max(0, width - nameWidth - gap) + 0.5
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        guard let width = proposal.width else {
            let value = subviews[1].sizeThatFits(.unspecified)
            return CGSize(width: nameWidth + gap + value.width, height: max(minHeight, value.height))
        }
        if isStacked(width: width, subviews: subviews) {
            let name = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let value = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: width, height: name.height + stackGap + max(value.height, minHeight - name.height))
        }
        let arrangement = inline(width: width, subviews: subviews)
        return CGSize(width: width, height: arrangement.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        subviews[2].place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
        if isStacked(width: bounds.width, subviews: subviews) {
            let name = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let value = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: name.height))
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + name.height + stackGap), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: value.height))
            return
        }
        let arrangement = inline(width: bounds.width, subviews: subviews)
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + arrangement.nameY), anchor: .topLeading,
            proposal: ProposedViewSize(width: nameWidth, height: arrangement.name.height))
        subviews[1].place(
            at: CGPoint(x: bounds.minX + nameWidth + gap, y: bounds.minY + arrangement.valueY), anchor: .topLeading,
            proposal: ProposedViewSize(width: arrangement.valueWidth, height: arrangement.value.height))
    }

    private struct Inline {
        var name: CGSize
        var value: CGSize
        var valueWidth: CGFloat
        var nameY: CGFloat
        var valueY: CGFloat
        /// Includes the name's own offset, so a name set level with a value's first line never runs past the row.
        var height: CGFloat { max(minHeight, nameY + name.height, valueY + value.height) }
        var minHeight: CGFloat
    }

    private func inline(width: CGFloat, subviews: Subviews) -> Inline {
        let valueWidth = max(0, width - nameWidth - gap)
        let nameProposal = ProposedViewSize(width: nameWidth, height: nil)
        let valueProposal = ProposedViewSize(width: valueWidth, height: nil)
        let name = subviews[0].sizeThatFits(nameProposal)
        let value = subviews[1].sizeThatFits(valueProposal)
        if value.height <= minHeight && name.height <= minHeight {
            return Inline(
                name: name, value: value, valueWidth: valueWidth, nameY: (minHeight - name.height) / 2,
                valueY: (minHeight - value.height) / 2, minHeight: minHeight)
        }
        // The value starts at the top, and the name sits level with its first line.
        let valueBaseline = subviews[1].dimensions(in: valueProposal)[.firstTextBaseline]
        let nameBaseline = subviews[0].dimensions(in: nameProposal)[.firstTextBaseline]
        return Inline(
            name: name, value: value, valueWidth: valueWidth, nameY: max(0, valueBaseline - nameBaseline), valueY: 0,
            minHeight: minHeight)
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

    /// A quietly filled, rounded chip around the view, for a value that has a shape of its own. It is not a
    /// control: a button or a menu takes `InspectorChipStyle` instead.
    func inspectorChip() -> some View {
        padding(.horizontal, InspectorMetrics.chipPadding / 2)
            .padding(.vertical, 3)
            .background(.quinary, in: .rect(cornerRadius: InspectorMetrics.chipRadius, style: .continuous))
    }
}

/// A button or a menu drawn as a chip: the same quiet fill as `inspectorChip`, a little stronger under the pointer.
struct InspectorChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration)
    }

    private struct ChipBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, InspectorMetrics.chipPadding / 2)
                .padding(.vertical, 3)
                .background(
                    configuration.isPressed || hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary),
                    in: .rect(cornerRadius: InspectorMetrics.chipRadius, style: .continuous))
                .contentShape(.rect(cornerRadius: InspectorMetrics.chipRadius, style: .continuous))
                .onHover { hovering = $0 }
        }
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

/// What a section's quiet "Add" row looks like: a plus and a title inside a dashed edge. It is the label of a
/// button or a menu.
struct InspectorAddLabel: View {
    let title: LocalizedStringKey
    @State private var hovering = false

    var body: some View {
        Label(title, systemImage: "plus")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, InspectorMetrics.chipPadding / 2)
            .padding(.vertical, 3)
            .background(hovering ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear), in: shape)
            .overlay { shape.strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            .contentShape(shape)
            .onHover { hovering = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: InspectorMetrics.chipRadius, style: .continuous)
    }
}

/// The quiet row that adds one thing to a section.
struct InspectorAddRow: View {
    let title: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { InspectorAddLabel(title: title) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
    }
}

/// The quiet row that adds one of several things to a section, from a menu.
struct InspectorAddMenu<Content: View>: View {
    let title: LocalizedStringKey
    let identifier: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            InspectorAddLabel(title: title)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// The context menu a row of the inspector offers: whether the page shows it too.
struct ShowOnPageMenu: View {
    let isShown: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle("Show on Page", isOn: Binding(get: { isShown }, set: { onChange($0) }))
            .accessibilityIdentifier("ShowOnPage")
    }
}

extension View {
    /// Offers Show on Page on the view, where the inspector can change it.
    @ViewBuilder func showOnPageMenu(isShown: Bool, onChange: ((Bool) -> Void)?) -> some View {
        if let onChange {
            contextMenu { ShowOnPageMenu(isShown: isShown, onChange: onChange) }
        } else {
            self
        }
    }
}
