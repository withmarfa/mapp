import SwiftUI

/// Where the page column shows one chosen item, several show a pile of cards: the item edited last on top and up to three
/// sheets behind it, with the count and what the items are under it ("4 Tasks", or "4 Items" where their types differ).
/// The capsule stands under it, over the same column (`selectionCapsule`). It shows nothing to read or edit.
struct SelectionPile: View {
    @CurrentLibrary private var library
    @Environment(SelectionSummary.self) private var summary: SelectionSummary?
    @Environment(\.interfaceTextSize) private var textSize

    /// The card's size at the default interface text size, which a column too small for it scales down.
    private static let card = CGSize(width: 324, height: 406)

    var body: some View {
        let facts = summary?.facts ?? SelectionFacts()
        let scale = InterfaceStyle.scale(for: textSize)
        GeometryReader { geometry in
            let room = SelectionSummary.capsuleRoom(scale: scale) + 48
            // The pile's sheets reach 28 points under the card, and the title stands under them.
            let fit = min(1, (geometry.size.width - 48) / (Self.card.width * scale), (geometry.size.height - room - 56) / (Self.card.height * scale + 28))
            VStack(spacing: 22) {
                if let item = facts.topID.flatMap(library.item) {
                    pile(of: item, behind: min(facts.count - 1, 3), scale: scale)
                        .frame(width: Self.card.width * scale, height: Self.card.height * scale)
                        .scaleEffect(max(fit, 0.3), anchor: .top)
                        .frame(width: Self.card.width * scale * max(fit, 0.3), height: (Self.card.height * scale + 28) * max(fit, 0.3), alignment: .top)
                    Text(verbatim: facts.title)
                        .font(.system(size: 13 * scale, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Clear of the capsule, which stands over the same column.
            .padding(.bottom, room - 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: facts.title))
        .accessibilityIdentifier("MultipleSelectionPrompt")
    }

    private func pile(of item: Item, behind: Int, scale: CGFloat) -> some View {
        ZStack {
            ForEach((1...max(behind, 1)).reversed(), id: \.self) { depth in
                if depth <= behind { PileSheet().modifier(PileTilt(depth: depth)) }
            }
            PileCard(item: item, scale: scale)
        }
    }
}

/// How far each sheet behind the top card sits: lower, turned a little, and a little smaller.
private struct PileTilt: ViewModifier {
    let depth: Int

    func body(content: Content) -> some View {
        switch depth {
        case 1: content.offset(y: 9).rotationEffect(.degrees(-3.2))
        case 2: content.offset(y: 17).rotationEffect(.degrees(3.8)).scaleEffect(0.98)
        default: content.offset(y: 28).rotationEffect(.degrees(-1.3)).scaleEffect(0.95)
        }
    }
}

private struct PileSheet: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.background)
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.055), radius: 11, y: 8)
    }
}

/// The top card: the item's type, its title and the start of its text, fading out toward the foot.
private struct PileCard: View {
    @CurrentLibrary private var library
    let item: Item
    let scale: CGFloat

    var body: some View {
        let catalogue = library.catalogue
        PileSheet()
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6 * scale) {
                    HStack(spacing: 6) {
                        TonedGlyph(id: catalogue.icon(for: item.type), size: 13 * scale)
                        Text(verbatim: catalogue.label(for: item.type))
                            .font(.system(size: 12 * scale, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 20 * scale)
                    Text(verbatim: item.displayTitle)
                        .font(.system(size: 20 * scale, weight: .bold))
                        .lineLimit(3)
                    if !item.preview.isEmpty {
                        Text(verbatim: item.preview)
                            .font(.system(size: 13 * scale))
                            .foregroundStyle(.secondary)
                            .lineSpacing(5 * scale)
                            .padding(.top, 6 * scale)
                    }
                }
                .padding(.horizontal, 26 * scale)
                .padding(.top, 24 * scale)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.background)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .init(x: 0.5, y: 0.9)))
                    .frame(height: 68 * scale)
                    .clipShape(.rect(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
                    .allowsHitTesting(false)
            }
    }
}
