import SwiftUI

/// Menu labels supply content only because AppKit renders native menu buttons itself.
struct ItemChipLabel: View {
    let title: Text
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            title.lineLimit(1).truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The shape sits outside native controls so they cannot strip its styling from their label.
    func itemChipStyle() -> some View {
        self
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(.quaternary, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
    }

    func itemChipMenuStyle() -> some View {
        self
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .buttonStyle(.plain)
            .controlSize(.regular)
            .itemChipStyle()
    }
}

/// Long parent names must not push every metadata control into a separate full-width row.
struct ItemChipLayout: Layout {
    var spacing: CGFloat = 8

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
