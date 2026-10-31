import AppKit
import MarfaIcons
import SwiftUI
import UniformTypeIdentifiers

/// What shape an item's card takes in the gallery. A file shows its own picture, an item whose type has a status
/// shows it as the page header's pin does, an item with a start date leads with a date block, and the rest are a
/// miniature of the page.
enum GalleryKind: Equatable {
    case note
    case file(UTType)
    case task(GalleryStatus)
    case event(GalleryEventDate)

    static func of(_ item: Item, in library: any ItemLibrary) -> GalleryKind {
        if case .file(let type, _) = item.content { return .file(type) }
        let info = library.catalogue.itemTypes[item.type]
        if let field = info?.statusField, let value = ItemPageHeader.statusValue(of: item, in: field) {
            return .task(GalleryStatus(
                label: ItemTypeInfo.Field.label(ofOption: value), mark: PageHeader.Mark(group: field.statusGroup(of: value))))
        }
        if let date = startDate(of: item, info: info, in: library) { return .event(GalleryEventDate(date: date)) }
        return .note
    }

    /// The first start-like date field the type declares. A type the catalogue does not describe, as a folder's
    /// events are, is known as an event by the type it builds on, and the usual names.
    private static func startDate(of item: Item, info: ItemTypeInfo?, in library: any ItemLibrary) -> Date? {
        var keys = (info?.fields ?? []).filter { field in
            guard case .date = field.kind else { return false }
            return field.key == "start" || field.key.hasPrefix("start_") || field.key.hasPrefix("starts")
        }.map(\.key)
        if keys.isEmpty, PageHeaderKind.of(item.type, in: library.catalogue) == .event {
            keys = ["start", "starts_at", "start_at", "start_date", "date"]
        }
        for key in keys {
            if let string = item.value(of: key)?.string, let date = ItemDate.parse(string)?.date { return date }
        }
        return nil
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
            (GalleryKind.of(item, in: library), GalleryArtworkCache.basis(of: item, in: library), library.catalogue.icon(for: item.type))
        }
        (kind, basis, icon) = made
    }
}

struct GalleryStatus: Equatable {
    let label: String
    let mark: PageHeader.Mark
}

struct GalleryEventDate: Equatable {
    let date: Date
    var weekday: String { date.formatted(.dateTime.weekday(.abbreviated)).uppercased() }
    var day: String { date.formatted(.dateTime.day()) }
}

/// One item in the gallery: a thumbnail, then its title and a line about it below, as Finder's icon view and the
/// Notes gallery lay it out. It takes only its own inputs and compares by them, so a selection that moves, or
/// another card's change, leaves its body alone; the selection ring (`GalleryRing`) reads the selection itself.
struct GalleryCard: View, Equatable {
    @CurrentLibrary private var library
    let item: Item
    /// Read only by the selection ring, which follows the selection on its own.
    let browser: Browser
    let order: NoteOrder
    /// Changes when the day does, since the line about the item reads as Today or Yesterday.
    let day: Int
    /// The thumbnail's width in points, which sets the scale of the miniature page.
    let width: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.browser === rhs.browser && lhs.order == rhs.order && lhs.day == rhs.day && lhs.width == rhs.width
    }

    var body: some View {
        let facts = GalleryCardFacts(of: item, in: library)
        VStack(alignment: .leading, spacing: 10) {
            GalleryThumbnail(item: item, browser: browser, facts: facts, width: width)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .interfaceFont(.subheadline.weight(.semibold))
                    // Two lines held for every title, so the cards of a row are the same height.
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    TypeIcon(id: facts.icon)
                    Text(NoteDate.listLabel(for: order.sort.date(of: item), now: library.now())).lineLimit(1)
                    if item.isFavorite { Image(systemName: "star.fill") }
                }
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// The picture on top of a card, 4 to 3 with a hairline edge and a soft shadow. The page is on the editor's own
/// background so a note's miniature reads as the note.
private struct GalleryThumbnail: View {
    @CurrentLibrary private var library
    @Environment(\.displayScale) private var displayScale
    let item: Item
    let browser: Browser
    let facts: GalleryCardFacts
    let width: CGFloat
    @State private var artwork: GalleryArtwork?

    private static let radius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let basis = facts.basis
        let shown = artwork ?? GalleryArtworkCache.peek(basis, width: width)
        Color(nsColor: .textBackgroundColor)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay { content(shown) }
            .clipShape(shape)
            .overlay { shape.strokeBorder(.separator, lineWidth: 1) }
            .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
            .overlay { GalleryRing(browser: browser, id: item.id, radius: Self.radius + 3) }
            .task(id: basis) {
                artwork = nil
                let made = await GalleryArtworkCache.artwork(for: item, width: width, scale: displayScale, in: library)
                if !Task.isCancelled { artwork = made }
            }
    }

    @ViewBuilder private func content(_ shown: GalleryArtwork?) -> some View {
        let kind = facts.kind
        let unit = min(1.6, max(0.85, width / 220))
        ZStack(alignment: .topLeading) {
            if let shown {
                Color.clear.overlay(alignment: shown.isDocument ? .top : .center) {
                    Image(decorative: shown.image, scale: displayScale).resizable().scaledToFill()
                }
                .clipped()
            } else if case .file(let type) = kind {
                FileGlyph(type: type)
            } else {
                PageMiniature(item: item, kind: kind, unit: unit)
            }
            if shown != nil { GalleryAccessory(kind: kind, unit: unit, onPicture: true).padding(10 * unit) }
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

/// A note as a small page: the title in a heading's weight, the text under it in small type, cut off at the foot.
private struct PageMiniature: View {
    let item: Item
    let kind: GalleryKind
    let unit: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5 * unit) {
            GalleryAccessory(kind: kind, unit: unit, onPicture: false)
            Text(item.displayTitle)
                .font(.system(size: 11 * unit, weight: .semibold))
                .lineLimit(2)
            if !item.preview.isEmpty {
                Text(item.preview)
                    .font(.system(size: 9 * unit))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5 * unit)
            }
            Spacer(minLength: 0)
        }
        .padding(12 * unit)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        }
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

/// What a task or event adds at the thumbnail's top leading corner.
private struct GalleryAccessory: View {
    let kind: GalleryKind
    let unit: CGFloat
    let onPicture: Bool

    var body: some View {
        switch kind {
        case .task(let status):
            HStack(spacing: 5 * unit) {
                StatusMark(mark: status.mark, size: 10 * unit)
                Text(status.label).font(.system(size: 10 * unit, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 8 * unit)
            .padding(.vertical, 4 * unit)
            .background(onPicture ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.quaternary), in: .capsule)
        case .event(let event):
            VStack(spacing: 0) {
                Text(event.weekday).font(.system(size: 8 * unit, weight: .semibold)).foregroundStyle(.red)
                Text(event.day).font(.system(size: 20 * unit, weight: .semibold)).monospacedDigit()
            }
            .frame(width: 38 * unit, height: 42 * unit)
            .background(onPicture ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color(nsColor: .textBackgroundColor)), in: .rect(cornerRadius: 8 * unit, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 8 * unit, style: .continuous).strokeBorder(.separator, lineWidth: 1) }
        case .note, .file:
            EmptyView()
        }
    }
}

/// The status ring the page header draws, in its color, with half or all of it filled.
struct StatusMark: View {
    let mark: PageHeader.Mark
    let size: CGFloat

    private var color: Color {
        switch mark.tone {
        case .orange: .orange
        case .red: .red
        case .green: .green
        case .grey, .neutral: Color.secondary
        }
    }

    var body: some View {
        Circle().strokeBorder(color, lineWidth: 1.5)
            .overlay {
                switch mark.fill {
                case .none: EmptyView()
                case .full: Circle().fill(color)
                case .half: Circle().fill(color).mask(alignment: .leading) { Rectangle().frame(width: size / 2) }
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
