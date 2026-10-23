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
/// text until it is hovered or focused.
struct InspectorRow<Value: View>: View {
    @Environment(\.interfaceTextSize) private var textSize
    /// Nil leaves the name column empty, for a row that belongs to the one above.
    let name: LocalizedStringKey?
    @ViewBuilder let value: Value

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(alignment: .firstTextBaseline, spacing: InspectorMetrics.gap * scale) {
            Text(name ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: InspectorMetrics.nameWidth * scale, alignment: .leading)
                .accessibilityHidden(name == nil)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .interfaceFont(.callout)
        .frame(minHeight: InspectorMetrics.rowHeight * scale)
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
    /// A value that reads as plain text, and shows the system's subtle fill only while hovered or focused.
    func inspectorValue(isFocused: Bool = false) -> some View {
        modifier(InspectorValueStyle(isFocused: isFocused))
    }
}

/// The text an empty value shows.
struct InspectorPlaceholder: View {
    var text: LocalizedStringKey = "Add"

    var body: some View {
        Text(text).foregroundStyle(.tertiary)
    }
}
