import Foundation

/// What an item page's header draws of the item, resolved once for every page that draws one: the note page's, which
/// sends it to the editor's web page (`ItemPageHeader`), and a saved web page's, drawn in SwiftUI (`WebPageItemPage`).
/// Both take their kind, their line and their pins from here, so they cannot disagree about what a header shows.
///
/// A saved web page draws the same header whichever look it is shown in. The look changes the title's type and what the
/// page below shows, never the pins or the lines.
struct PageHeaderParts {
    let type: ItemTypeInfo?
    let kind: PageHeaderKind
    let lead: PageHeaderLead
    let relationships: [ItemRelationship]
    let placement: PagePlacement
    let now: Date
    /// Every row the item could show, before the person's choice (`PropertyRow.candidates`).
    let candidates: [PropertyRow]
    let pins: PagePins

    /// `offersEmpty` is for the page that edits values: a value the item does not have yet is an empty chip there.
    init(of item: Item, in library: any ItemLibrary, placements: PagePlacements, dateFormat: DateFormat, offersEmpty: Bool = false) {
        type = library.catalogue.itemTypes[item.type]
        placement = placements.placement(of: item.type, in: library.catalogue)
        relationships = library.relationships(for: item.id)
        now = library.now()
        kind = PageHeaderKind.of(item.type, in: library.catalogue)
        lead = PageHeaderLead(
            for: item, kind: kind, body: kind == .reading ? library.body(of: item.id)?.text : nil, now: now, format: dateFormat)
        let type = type, relationships = relationships
        candidates = PropertyRow.candidates(
            of: item, type: type, hidden: library.hiddenPropertyKeys(of: item).union(lead.consumed), relationships: relationships,
            parentField: PagePlacement.parent, format: dateFormat, tags: library.tags(of: item),
            typeLabel: type.map { ItemPageHeader.localized($0.label) }, typeIcon: library.catalogue.icon(for: item.type),
            sourceName: item.source.map { library.sources.name($0) }, now: now, calendar: .current, locale: .current,
            offersEmpty: offersEmpty, icon: { Self.typeIcon(of: $0, in: library) }, isPerson: { Self.isPerson($0, in: library) })
        pins = PagePins.resolve(
            for: item, type: type, placement: placement, lead: lead, relationships: relationships, candidates: candidates, offersEmpty: offersEmpty,
            icon: { Self.typeIcon(of: $0, in: library) }, isPerson: { Self.isPerson($0, in: library) })
    }

    /// The icon of the type of the item `target` names.
    static func typeIcon(of target: ItemID, in library: any ItemLibrary) -> String? {
        library.item(target).flatMap { library.catalogue.icon(for: $0.type) }
    }

    private static func isPerson(_ target: ItemID, in library: any ItemLibrary) -> Bool {
        library.item(target).map { PageHeaderKind.of($0.type, in: library.catalogue) == .person } ?? false
    }
}
