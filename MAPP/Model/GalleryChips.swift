import Foundation
import Marfa

/// A property a gallery's card can show under its subtext: one of the columns the place's table offers, or the item's
/// tags. The identifier is the column's (`ItemTableColumn.id`), so the table and the gallery name a property alike.
nonisolated struct GalleryProperty: Identifiable, Hashable, Sendable {
    static let tagsID = "tags"

    let id: String
    let label: String

    /// The properties a place offers, in the table's order: every column but the name and the type, which the card
    /// shows on its own, and the tags where an item holds any. The property a view chose but its items no longer
    /// hold is not offered here and is not forgotten (`ViewCards.properties`).
    static func offered(columns: [ItemTableColumn], rows: [ItemTableRow]) -> [GalleryProperty] {
        var offered = columns.filter { $0.content != .title && $0.content != .type }.map { GalleryProperty(id: $0.id, label: $0.label) }
        if rows.contains(where: { !$0.item.tags.subtracting([ItemTag.favorite]).isEmpty }) {
            offered.append(GalleryProperty(id: tagsID, label: String(localized: "Tags")))
        }
        return offered
    }
}

/// One chip of a card, which its card draws in the app's value chips. A value the chips cannot draw is not one.
nonisolated struct GalleryChip: Hashable, Sendable {
    enum Look: Hashable, Sendable {
        /// A word with no mark of its own, such as a date or a number.
        case plain
        /// A choice or one word of a list, with a dot in its own color.
        case option
        case tag
        /// A status with the ring of its group.
        case status(PageHeader.Mark)
        /// An item this one links to, with its type's mark.
        case link(icon: String?)
    }

    let text: String
    let look: Look

    /// The chips for one property of one item, in order: none where the item holds no value, or the property is one
    /// the item's type does not have. This reads the item and the catalogue only.
    @MainActor
    static func chips(
        for property: String, of item: Item, in library: any ItemLibrary, format: DateFormat, now: Date
    ) -> [GalleryChip] {
        let chips: [GalleryChip]
        switch property {
        case GalleryProperty.tagsID:
            chips = item.tags.subtracting([ItemTag.favorite]).sorted().map { GalleryChip(text: $0, look: .tag) }
        case ItemTableColumn.parent.id:
            chips = item.parentID.flatMap { library.item($0) }.map {
                [GalleryChip(text: $0.displayTitle, look: .link(icon: library.catalogue.icon(for: $0.type)))]
            } ?? []
        case ItemTableColumn.created.id:
            chips = [day(item.created, library: library, format: format, now: now)]
        case ItemTableColumn.edited.id:
            chips = [day(item.modified, library: library, format: format, now: now)]
        case "duration":
            chips = duration(of: item).map { [GalleryChip(text: $0, look: .plain)] } ?? []
        default:
            guard property.hasPrefix(fieldPrefix),
                  let field = library.catalogue.itemTypes[item.type]?.fields.first(where: { fieldPrefix + $0.key == property })
            else { return [] }
            chips = value(of: field, in: item, library: library, format: format)
        }
        return chips.filter { !$0.text.isEmpty }
    }

    private static let fieldPrefix = "field."

    private static func day(_ date: Date, library: any ItemLibrary, format: DateFormat, now: Date) -> GalleryChip {
        GalleryChip(text: DateDisplay.text(of: date, hasTime: false, place: .table, format: format, now: now), look: .plain)
    }

    /// The time between a start and an end, as the table's Duration column reads it.
    private static func duration(of item: Item) -> String? {
        guard let start = item.value(of: "starts_at")?.string.flatMap({ ItemDate.parse($0)?.date }),
              let end = item.value(of: "ends_at")?.string.flatMap({ ItemDate.parse($0)?.date }), end >= start else { return nil }
        return Duration.seconds(end.timeIntervalSince(start))
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    @MainActor
    private static func value(
        of field: ItemTypeInfo.Field, in item: Item, library: any ItemLibrary, format: DateFormat
    ) -> [GalleryChip] {
        if field.isStatus {
            guard let word = PagePins.statusValue(of: item, in: field) else { return [] }
            let mark = PageHeader.Mark(group: field.statusGroup(of: word))
            return [GalleryChip(text: ItemTypeInfo.Field.label(ofOption: word), look: .status(mark))]
        }
        guard let value = PropertyRow.value(of: field, in: item, format: format) else { return [] }
        switch value {
        case .options(let words): return words.map { GalleryChip(text: $0, look: .option) }
        case .people(let names): return names.map { GalleryChip(text: $0, look: .plain) }
        case .items(let targets): return targets.map { GalleryChip(text: $0.title, look: .link(icon: $0.icon)) }
        case .date(let text), .text(let text), .url(let text), .email(let text), .phone(let text):
            return [GalleryChip(text: text.trimmingCharacters(in: .whitespacesAndNewlines), look: .plain)]
        case .boolean(let flag):
            return [GalleryChip(text: flag ? String(localized: "Yes") : String(localized: "No"), look: .plain)]
        case .status, .parent, .type, .source, .tags, .when:
            return []
        }
    }
}
