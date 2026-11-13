import AppKit
import Marfa
import MarfaIcons
import SwiftUI
import UniformTypeIdentifiers

/// What shape an item's card takes in the gallery: a file shows its own picture, and every other item is a miniature of
/// its opening lines. What a card says is its type's look, never its shape.
enum GalleryKind: Equatable {
    case note
    case file(UTType)

    static func of(_ item: Item) -> GalleryKind {
        if case .file(let type, _) = item.content { return .file(type) }
        return .note
    }
}

/// What a card derives from its item, the catalogue and the files its text embeds: its shape, what decides its
/// picture and its type's icon. It is read when the card's own inputs change, never for another card's selection.
struct GalleryCardFacts {
    let kind: GalleryKind
    let basis: GalleryArtworkCache.Basis
    let icon: String?

    init(of item: Item, in library: any ItemLibrary) {
        let made = Cost.measure(.galleryCard) {
            (GalleryKind.of(item), GalleryArtworkCache.basis(of: item, in: library), library.catalogue.icon(for: item.type))
        }
        (kind, basis, icon) = made
    }
}

/// One item in the gallery, as Finder's icon view and the Notes gallery lay it out: a picture, or the item's opening
/// lines where it has none, then its title and the line its type's look gives it. It takes only its own inputs, the
/// view's choices (`cards`) and what the card says (`content`, worked out once for each item by `CardContents`), and
/// compares by them, so a selection that moves, or another card's change, leaves its body alone; the selection ring
/// (`GalleryRing`) reads the selection itself.
struct GalleryCard: View, Equatable {
    @CurrentLibrary private var library
    let item: Item
    /// Read only by the selection ring, which follows the selection on its own.
    let browser: Browser
    /// The picture's width in points, which sets the scale of the opening lines drawn on it.
    let width: CGFloat
    /// What the view chose for its cards: the picture's preview, whether it is fitted, and the size.
    let cards: ViewCards
    let content: RowContent

    static let radius: CGFloat = 10

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.browser === rhs.browser && lhs.width == rhs.width && lhs.cards == rhs.cards && lhs.content == rhs.content
    }

    var body: some View {
        let facts = GalleryCardFacts(of: item, in: library)
        VStack(alignment: .leading, spacing: 10) {
            if cards.preview == .none {
                words
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: Self.radius, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(.separator, lineWidth: 1) }
                    .overlay(alignment: .topTrailing) { if item.isFavorite { FavoriteBadge(unit: 1).padding(6) } }
                    .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
                    .overlay { GalleryRing(browser: browser, id: item.id, radius: Self.radius + 3) }
            } else {
                GalleryThumbnail(item: item, browser: browser, facts: facts, width: width, cards: cards)
                words.padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The title, then the line its type's look gives it. Both keep their room, so the cards of a row are one height.
    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.title)
                .interfaceFont(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(verbatim: content.secondary ?? " ")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
    }
}

/// A favorite's star on the picture's corner, the one mark a card puts on its picture.
private struct FavoriteBadge: View {
    let unit: CGFloat

    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 10 * unit))
            .foregroundStyle(.yellow)
            .padding(5 * unit)
            .background(.regularMaterial, in: .circle)
            .accessibilityHidden(true)
    }
}

/// The picture on top of a card, 4 to 3 with a hairline edge and a soft shadow. What fills it is the view's choice of
/// preview: the item's picture or else its opening lines, either alone, and a picture cut to fill or shown whole. An
/// item with neither shows its type's mark, quietly, so no card is an empty frame.
private struct GalleryThumbnail: View {
    @CurrentLibrary private var library
    @Environment(\.displayScale) private var displayScale
    let item: Item
    let browser: Browser
    let facts: GalleryCardFacts
    let width: CGFloat
    let cards: ViewCards
    @State private var artwork: GalleryArtwork?

    private static let radius = GalleryCard.radius

    private struct Loading: Hashable {
        let basis: GalleryArtworkCache.Basis
        let loads: Bool
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let basis = facts.basis
        let loads = cards.preview.showsPicture
        let shown = loads ? (artwork ?? GalleryArtworkCache.peek(basis, width: width)) : nil
        let unit = min(1.6, max(0.85, width / 220))
        Color(nsColor: .textBackgroundColor)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay { content(shown, unit: unit) }
            .overlay(alignment: .topTrailing) { if item.isFavorite { FavoriteBadge(unit: unit).padding(8 * unit) } }
            .clipShape(shape)
            .overlay { shape.strokeBorder(.separator, lineWidth: 1) }
            .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
            .overlay { GalleryRing(browser: browser, id: item.id, radius: Self.radius + 3) }
            .task(id: Loading(basis: basis, loads: loads)) {
                artwork = nil
                guard loads else { return }
                let made = await GalleryArtworkCache.artwork(for: item, width: width, scale: displayScale, in: library)
                if !Task.isCancelled { artwork = made }
            }
    }

    @ViewBuilder private func content(_ shown: GalleryArtwork?, unit: CGFloat) -> some View {
        if let shown {
            Color.clear.overlay(alignment: shown.isDocument && !cards.fitsPicture ? .top : .center) {
                let image = Image(decorative: shown.image, scale: displayScale).resizable()
                if cards.fitsPicture { image.scaledToFit() } else { image.scaledToFill() }
            }
            .clipped()
        } else if cards.preview != .text, case .file(let type) = facts.kind {
            FileGlyph(type: type)
        } else if !item.preview.isEmpty, cards.preview != .picture {
            OpeningLines(text: item.preview, unit: unit)
        } else {
            QuietMark(icon: facts.icon)
        }
    }
}

/// The ring around a selected card's picture. It reads the selection itself, so a selection that moves redraws the
/// rings and no card.
private struct GalleryRing: View {
    let browser: Browser
    let id: ItemID
    let radius: CGFloat

    var body: some View {
        if browser.selection.contains(id) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 3)
                .padding(-3)
        }
    }
}

/// The item's opening lines, in small type, cut off at the foot. The title is under the picture, so it is not here.
private struct OpeningLines: View {
    let text: String
    let unit: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 9.5 * unit))
            .foregroundStyle(.secondary)
            .lineSpacing(1.5 * unit)
            .padding(12 * unit)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
            }
    }
}

/// An item with no picture and no text: its type's mark, large and quiet.
private struct QuietMark: View {
    let icon: String?

    var body: some View {
        GeometryReader { geometry in
            Image(typeGlyph: icon)
                .resizable().scaledToFit()
                .frame(width: geometry.size.height * 0.3, height: geometry.size.height * 0.3)
                .foregroundStyle(.quaternary)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}

/// A file with no picture of its own yet: its type's icon, large and centered.
private struct FileGlyph: View {
    let type: UTType

    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: NSWorkspace.shared.icon(for: type))
                .resizable().scaledToFit()
                .frame(width: geometry.size.height * 0.62, height: geometry.size.height * 0.62)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}
