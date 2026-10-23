import SwiftUI

/// A pinned property as the page draws it under a title, for a new item's page before it has one: a symbol in the
/// secondary color, the value, and a chevron. An empty pin shows a plus. Menu labels supply content only because
/// AppKit renders native menu buttons itself, so the shape is `itemPinStyle`.
struct ItemPinLabel: View {
    @Environment(\.interfaceTextSize) private var textSize
    let title: Text
    var systemImage: String
    var isEmpty = false

    var body: some View {
        HStack(spacing: 5 * InterfaceStyle.scale(for: textSize)) {
            Image(systemName: isEmpty ? "plus" : systemImage)
                .foregroundStyle(.secondary)
            title.lineLimit(1).truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 9 * InterfaceStyle.scale(for: textSize), weight: .bold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ItemPinStyle: ViewModifier {
    @Environment(\.interfaceTextSize) private var textSize
    @State private var hovering = false
    let isEmpty: Bool

    func body(content: Content) -> some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let shape = RoundedRectangle(cornerRadius: 6 * scale)
        content
            .font(.system(size: 12 * scale, weight: .medium))
            .foregroundStyle(isEmpty ? .secondary : .primary)
            .padding(.horizontal, 8 * scale)
            .frame(height: 24 * scale)
            .background(hovering ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear), in: shape)
            .overlay { shape.strokeBorder(isEmpty ? AnyShapeStyle(.quinary) : AnyShapeStyle(.separator), lineWidth: 1) }
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// The shape sits outside native controls so they cannot strip its styling from their label: a hairline
    /// edge and no fill, which hover fills.
    func itemPinStyle(isEmpty: Bool = false) -> some View {
        modifier(ItemPinStyle(isEmpty: isEmpty))
    }

    func itemPinMenuStyle(isEmpty: Bool = false) -> some View {
        self
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .itemPinStyle(isEmpty: isEmpty)
    }
}

/// Long parent names must not push every pin into a separate full-width row.
struct ItemPinLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(width: proposal.width, subviews: subviews)
        let width: CGFloat
        if let proposedWidth = proposal.width, proposedWidth.isFinite { width = max(0, proposedWidth) }
        else { width = frames.map(\.maxX).max() ?? 0 }
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(width: bounds.width, subviews: subviews)
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat?, subviews: Subviews) -> [CGRect] {
        let available: CGFloat
        if let width, width.isFinite { available = max(0, width) } else { available = .infinity }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        return subviews.map { view in
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(ideal.width, available), height: ideal.height))
            if x > 0 && x + size.width > available {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            let frame = CGRect(x: x, y: y, width: min(size.width, available), height: size.height)
            x += frame.width + spacing
            rowHeight = max(rowHeight, frame.height)
            return frame
        }
    }
}
