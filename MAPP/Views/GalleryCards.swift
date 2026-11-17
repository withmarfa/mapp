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
/// picture, where the picture may come from and its type's icon. It is read when the card's own inputs change, never
/// for another card's selection.
struct GalleryCardFacts {
    let kind: GalleryKind
    let basis: GalleryArtworkCache.Basis
    let sources: [CardPicture.Source]
    let icon: String?

    init(of item: Item, in library: any ItemLibrary) {
        let made = Cost.measure(.galleryCard) {
            let attachments = item.isFile ? [] : library.attachments(of: item.id).compactMap { library.item($0) }
            return (
                GalleryKind.of(item), GalleryArtworkCache.basis(of: item, in: library),
                CardPicture.sources(of: item, attachments: attachments), library.catalogue.icon(for: item.type))
        }
        (kind, basis, sources, icon) = made
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
    /// What the view chose for its cards: the picture's preview, whether it is fitted, its shape and the size.
    let cards: ViewCards
    let content: RowContent

    static let radius: CGFloat = 10

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.browser === rhs.browser && lhs.width == rhs.width && lhs.cards == rhs.cards && lhs.content == rhs.content
    }

    var body: some View {
        let facts = GalleryCardFacts(of: item, in: library)
        let radius = cards.size == .small ? 8 : Self.radius
        VStack(alignment: .leading, spacing: 8) {
            if cards.preview == .none {
                words
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: radius, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.separator, lineWidth: 0.5) }
                    .overlay(alignment: .topTrailing) { if item.isFavorite { FavoriteBadge(unit: 1).padding(6) } }
                    .overlay { GalleryRing(browser: browser, id: item.id, shape: GalleryShape(cards: cards, radius: radius)) }
            } else {
                GalleryThumbnail(item: item, browser: browser, facts: facts, width: width, cards: cards, radius: radius)
                words.padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The title, then the line its type's look gives it, the Secondary line directly under the title. Every card reserves two title
    /// lines and one Secondary line, so every row is one height.
    private var words: some View {
        let large = cards.size == .large
        let titleFont = large ? Font.body.weight(.medium) : Font.callout.weight(.medium)
        let secondaryFont = large ? Font.callout : Font.subheadline
        // The words sit at the top of a block that always holds two title lines and one Secondary line.
        return ZStack(alignment: .topLeading) {
            lines(titleFont: titleFont, secondaryFont: secondaryFont, title: "", secondary: " ", reserves: true).hidden()
            lines(titleFont: titleFont, secondaryFont: secondaryFont, title: content.title, secondary: content.secondary ?? "", reserves: false)
        }
        .foregroundStyle(.primary)
    }

    private func lines(titleFont: Font, secondaryFont: Font, title: String, secondary: String, reserves: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .interfaceFont(titleFont)
                .lineLimit(2, reservesSpace: reserves)
                .multilineTextAlignment(.leading)
            Text(verbatim: secondary)
                .interfaceFont(secondaryFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// The outline of a card's picture area: rounded all round, or, for a book's cover, squarer at the spine.
private nonisolated struct GalleryShape: InsettableShape {
    let cards: ViewCards
    let radius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        if cards.shape == .cover {
            return UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 6, topTrailingRadius: 6, style: .continuous).path(in: rect)
        }
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }

    func inset(by amount: CGFloat) -> GalleryShape {
        var shape = self
        shape.insetAmount += amount
        return shape
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

/// The picture on top of a card, in the view's shape with a hairline edge. What fills it is `CardFace`: the item's
/// picture or else its opening lines, either alone, and a picture cut to fill or shown whole. A picture is made off the
/// main thread and cached, and a quiet frame stands in until it is ready. An item with neither a picture nor text shows
/// its type's mark, so no card is an empty frame.
private struct GalleryThumbnail: View {
    @CurrentLibrary private var library
    @Environment(\.displayScale) private var displayScale
    let item: Item
    let browser: Browser
    let facts: GalleryCardFacts
    let width: CGFloat
    let cards: ViewCards
    let radius: CGFloat
    @State private var artwork: GalleryArtwork?
    /// Whether making the picture has ended, with or without one, so a card does not show its fallback while it waits.
    @State private var resolved = false

    private struct Loading: Hashable {
        let basis: GalleryArtworkCache.Basis
        let loads: Bool
    }

    var body: some View {
        let shape = GalleryShape(cards: cards, radius: radius)
        let basis = facts.basis
        let face = CardFace.of(preview: cards.preview, sources: facts.sources, isFile: item.isFile, text: item.preview)
        let loads = face == .picture
        let shown = loads ? (artwork ?? GalleryArtworkCache.peek(basis, width: width)) : nil
        let unit = min(1.6, max(0.85, width / 220))
        Color(nsColor: .textBackgroundColor)
            .aspectRatio(cards.shape.aspect, contentMode: .fit)
            .overlay { content(shown, face: face, waiting: loads && !resolved, unit: unit) }
            .overlay(alignment: .topTrailing) { if item.isFavorite { FavoriteBadge(unit: unit).padding(8 * unit) } }
            .clipShape(shape)
            .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
            .overlay { GalleryRing(browser: browser, id: item.id, shape: GalleryShape(cards: cards, radius: radius)) }
            .task(id: Loading(basis: basis, loads: loads)) {
                artwork = nil
                resolved = GalleryArtworkCache.peek(basis, width: width) != nil
                guard loads else { return }
                let made = await GalleryArtworkCache.artwork(for: item, width: width, scale: displayScale, in: library)
                if !Task.isCancelled {
                    artwork = made
                    resolved = true
                }
            }
    }

    @ViewBuilder private func content(_ shown: GalleryArtwork?, face: CardFace, waiting: Bool, unit: CGFloat) -> some View {
        if let shown {
            Color.clear.overlay(alignment: shown.isDocument && !cards.fitsPicture ? .top : .center) {
                let image = Image(decorative: shown.image, scale: displayScale).resizable()
                if cards.fitsPicture { image.scaledToFit() } else { image.scaledToFill() }
            }
            .clipped()
        } else if waiting {
            Color.primary.opacity(0.03)
        } else {
            switch CardFace.fallback(preview: cards.preview, isFile: item.isFile, text: item.preview) {
            case .fileIcon:
                if case .file(let type) = facts.kind { FileGlyph(type: type) }
            case .text: OpeningLines(text: item.preview, unit: cards.size == .large ? 12.0 / 11 : 1)
            case .picture, .placeholder: QuietMark(icon: facts.icon)
            }
        }
    }
}

/// The ring around a selected card's picture, in the accent color with a gap of the window's color, as a Finder icon's
/// is. It reads the selection itself, so a selection that moves redraws the rings and no card.
private struct GalleryRing: View {
    let browser: Browser
    let id: ItemID
    let shape: GalleryShape

    var body: some View {
        if browser.selection.contains(id) {
            shape
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(-4)
        }
    }
}

/// The item's opening lines, in small type, cut off at the foot. The title is under the picture, so it is not here.
private struct OpeningLines: View {
    let text: String
    let unit: CGFloat

    var body: some View {
        Text(OpeningText.attributed(from: text))
            .font(.system(size: 11 * unit))
            .foregroundStyle(.secondary)
            .lineSpacing(2 * unit)
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
