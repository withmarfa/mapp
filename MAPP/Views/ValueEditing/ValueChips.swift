import MarfaIcons
import SwiftUI

/// The mark at the start of a row or a chip: a status ring, a person's initials, a tag, a choice's dot, a type's icon or
/// a symbol. It takes the same room whatever it is, so titles in a list start at one edge.
struct ValueMarkView: View {
    let mark: ValueListRow.Mark
    let scale: CGFloat
    var onAccent = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch mark {
        case .none:
            EmptyView()
        case .status(let group):
            StatusMark(mark: .init(group: group), size: 10 * scale).frame(width: 14 * scale)
        case .person(let initials):
            Text(verbatim: initials)
                .font(.system(size: 8 * scale, weight: .semibold))
                .frame(width: 18 * scale, height: 18 * scale)
                .background(.quaternary, in: .circle)
                .foregroundStyle(onAccent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .accessibilityHidden(true)
        case .tag:
            glyph("tag")
        case .symbol(let name):
            glyph(name)
        case .dot(let word):
            Circle()
                .fill(OptionTone.tone(for: word).color(for: scheme))
                .frame(width: 8 * scale, height: 8 * scale)
                .frame(width: 14 * scale)
                .accessibilityHidden(true)
        case .type(let icon):
            TypeGlyph(id: icon)
                .foregroundStyle(onAccent ? AnyShapeStyle(.white) : AnyShapeStyle(TypeTone(icon: icon).color(for: scheme)))
                .frame(width: 14 * scale, height: 14 * scale)
                .accessibilityHidden(true)
        }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11 * scale))
            .foregroundStyle(onAccent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: 14 * scale)
            .accessibilityHidden(true)
    }
}

/// A value the panel holds, in its search field, with an x that takes it away. VoiceOver reads it as "<name>, remove".
struct ValueChipView: View {
    let chip: ValueChip
    let scale: CGFloat
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4 * scale) {
            ValueMarkView(mark: chip.mark, scale: scale)
            Text(verbatim: chip.title).lineLimit(1).truncationMode(.tail)
            if chip.isRemovable {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 8 * scale, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
        .font(.system(size: 12 * scale))
        .padding(.leading, 6 * scale)
        .padding(.trailing, (chip.isRemovable ? 6 : 8) * scale)
        .frame(height: 20 * scale)
        .background(.quaternary, in: .rect(cornerRadius: 5 * scale, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.isRemovable ? Text("\(chip.title), remove") : Text(verbatim: chip.title))
        .modifier(RemovableChip(isRemovable: chip.isRemovable, remove: remove))
    }
}

private struct RemovableChip: ViewModifier {
    let isRemovable: Bool
    let remove: () -> Void

    func body(content: Content) -> some View {
        if isRemovable {
            content.accessibilityAddTraits(.isButton).accessibilityAction(.default, remove)
        } else {
            content
        }
    }
}

/// Lays out chips in a row that wraps, with the typed query as the last item taking what is left of the last row.
struct ChipFieldLayout: Layout {
    var spacing: CGFloat
    var lineHeight: CGFloat
    /// The least width the query is given before it moves to a row of its own.
    var queryFloor: CGFloat = 40

    private func frames(in width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        for index in subviews.indices {
            let isQuery = index == subviews.count - 1
            var size = subviews[index].sizeThatFits(.unspecified)
            size.height = isQuery ? lineHeight : max(size.height, 0)
            if isQuery {
                if x > 0, width - x < queryFloor {
                    x = 0
                    y += lineHeight + spacing
                }
                size.width = max(width - x, queryFloor)
            } else {
                size.width = min(size.width, width)
                if x > 0, x + size.width > width {
                    x = 0
                    y += lineHeight + spacing
                }
            }
            let top = y + (lineHeight - size.height) / 2
            frames.append(CGRect(x: x, y: top, width: size.width, height: size.height))
            x += size.width + spacing
        }
        return (frames, y + lineHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 240
        return CGSize(width: width, height: frames(in: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = frames(in: bounds.width, subviews: subviews)
        for (index, frame) in laid.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}
