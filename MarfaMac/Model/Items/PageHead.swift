import Foundation

/// What an item's page shows above its text: the kicker, the pins and the rows. The one model for every page that draws a
/// head, the editor's web page (`ItemPageHeader`) and a saved web page's SwiftUI head (`WebPageItemPage`), so they cannot
/// disagree. The page draws what this says and decides nothing.
///
/// The rows are every property the type offers, in the person's order for the type (`PagePlacement.ordered`), each
/// once. Those shown before Show More are the first `shownLimit` of the rows that have a value or that the person set
/// to Always Show, or, for a type with no text, of every row the person has not hidden. The rest are `folded`, and a
/// hidden row is also `muted`. An event's time is its first row, When, whatever the person chose.
///
/// The values no field describes (`PropertyRow.section`) come last, always folded and read only, under a heading of their
/// own, and have no place in the person's order.
///
/// Pins are made only while pinned properties are on (`PinsProperties`). A pinned row leaves the rows.
nonisolated struct PageHead: Equatable, Sendable {
    /// The grey line over the title: the type's mark and name, then what is true of the item among Read Only, Feed and
    /// Archived.
    struct Kicker: Equatable, Sendable {
        enum Flag: String, CaseIterable, Sendable {
            case readOnly, feed, archived

            var words: String {
                switch self {
                case .readOnly: String(localized: "Read Only")
                case .feed: String(localized: "Feed")
                case .archived: String(localized: "Archived")
                }
            }

            var symbol: String {
                switch self {
                case .readOnly: "lock"
                case .feed: SidebarPlace.feed.symbol ?? "tray"
                case .archived: "archivebox"
                }
            }
        }

        let typeName: String
        /// The type's icon, an Iconify ID.
        let typeIcon: String?
        /// Whether the type's name opens Change Type.
        let changesType: Bool
        let flags: [Flag]

        /// What VoiceOver reads for the line: "Task, Read Only, Feed".
        var spoken: String { ([typeName] + flags.map(\.words)).joined(separator: ", ") }
    }

    /// Most rows shown before Show More.
    static let shownLimit = 6

    let kicker: Kicker
    let pins: [PropertyRow]
    /// Every row, in order; those folded until Show More are marked so.
    let rows: [PropertyRow]

    /// How many rows wait under Show More.
    var foldedCount: Int { rows.count { $0.folded } }

    /// "Show 10 More". The page draws these words and never counts.
    var showMore: String { String(localized: "Show \(foldedCount) More") }

    /// The rows' identifiers in the order the page lists them, which a move in the row's menu works from. The rows for
    /// values no field describes (`section`) are in no order.
    var order: [String] { rows.filter { $0.section == nil }.map(\.id) }

    init(kicker: Kicker, pins: [PropertyRow], rows: [PropertyRow]) {
        self.kicker = kicker
        self.pins = pins
        self.rows = rows
    }

    /// The head of `item` as `library` holds it.
    @MainActor
    init(
        of item: Item, in library: any ItemLibrary, placements: PagePlacements = .stored(), pinsProperties: Bool = PinsProperties.stored(),
        dateFormat: DateFormat = .stored(), showsCoordinates: Bool = ShowsCoordinates.stored(), now: Date? = nil
    ) {
        let catalogue = library.catalogue
        let type = catalogue.itemTypes[item.type]
        let placement = placements.placement(of: item.type, in: catalogue)
        let now = now ?? library.now()
        let event = PageHeaderKind.of(item.type, in: catalogue) == .event ? EventHeader(item: item, now: now) : nil
        let candidates = PropertyRow.candidates(
            of: item, type: type, hidden: library.hiddenPropertyKeys(of: item).union(event == nil ? [] : EventHeader.keys),
            links: library.relationFields(of: item.id), format: dateFormat, tags: library.tags(of: item),
            showsCoordinates: showsCoordinates, isPriority: { catalogue.isPriority($0, of: $0.declaredBy) },
            icon: { PageHead.typeIcon(of: $0, in: library) }, isPerson: { PageHead.isPerson($0, in: library) },
            label: { catalogue.label(ofField: $0, for: item.type) })
        let when = event.map {
            PropertyRow(id: PagePlacement.when, label: String(localized: "When"), value: .when($0.time, note: $0.note), help: $0.help)
        }
        self.init(
            kicker: Kicker(
                typeName: type.map { Self.localized($0.label) } ?? catalogue.label(for: item.type), typeIcon: catalogue.icon(for: item.type),
                changesType: library.offersTypeChange(for: [item.id]),
                flags: Kicker.Flag.allCases.filter {
                    switch $0 {
                    case .readOnly: item.readOnly
                    case .feed: item.tier == .feed
                    case .archived: item.state == .archived
                    }
                }),
            candidates: candidates, when: when, placement: placement, pinsProperties: pinsProperties, hasText: type?.bodyKey != nil)
    }

    /// Chooses what shows from every row the item could show (`PropertyRow.candidates`).
    init(kicker: Kicker, candidates: [PropertyRow], when: PropertyRow?, placement: PagePlacement, pinsProperties: Bool, hasText: Bool) {
        var pins: [PropertyRow] = []
        if pinsProperties {
            pins = placement.pins.compactMap { id in candidates.first { $0.id == id && (!$0.isEmpty || $0.editable) } }.map(Self.capped)
        }
        let pinned = Set(pins.map(\.id))
        let listed = placement.ordered(candidates.filter { !pinned.contains($0.id) && $0.section == nil }, id: \.id)
        let others = candidates.filter { $0.section != nil }.map { row in
            var row = row
            row.folded = true
            return row
        }
        let leading = listed.filter { row in
            switch placement.shows(row.id) {
            case .hidden: false
            case .always: true
            case .whenSet: !hasText || !row.isEmpty
            }
        }
        let shown = Set(([when].compactMap { $0 } + leading).prefix(Self.shownLimit).map(\.id))
        let rows = ([when].compactMap { $0 } + listed).map { row in
            var row = row
            row.folded = !shown.contains(row.id)
            row.muted = placement.shows(row.id) == .hidden
            return row
        } + others
        self.init(kicker: kicker, pins: pins, rows: rows)
    }

    /// Most values of a list a pin shows before "+N more": the first, so it can be shown whole.
    static let listLimit = 1

    /// What a pin says of the values of a list it left out: "+4 more". The page draws these words and never makes them.
    static func moreText(_ count: Int) -> String { String(localized: "+\(count) more") }

    /// A list shows its first `listLimit` values, and how many it left out, and keeps the words of all of them as its
    /// help; any other row is as it was.
    static func capped(_ row: PropertyRow) -> PropertyRow {
        func cut<Value>(_ values: [Value], _ make: ([Value]) -> PropertyRow.Value) -> PropertyRow {
            guard values.count > listLimit else { return row }
            var cut = row
            cut.value = make(Array(values.prefix(listLimit)))
            cut.more = values.count - listLimit
            cut.help = row.wholeValue
            cut.optionTones = Array(row.optionTones.prefix(listLimit))
            return cut
        }
        switch row.value {
        case .items(let values): return cut(values) { .items($0) }
        case .people(let values): return cut(values) { .people($0) }
        case .options(let values): return cut(values) { .options($0) }
        case .tags(let values): return cut(values) { .tags($0) }
        default: return row
        }
    }

    /// The status the item holds, if it holds one.
    static func statusValue(of item: Item, in field: ItemTypeInfo.Field) -> String? {
        item.value(of: field.key)?.string.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A number dialed as its digits and a leading plus, whatever spacing it is written with; nil where it has none.
    static func dialAddress(_ number: String) -> URL? {
        var dialed = ""
        for (index, character) in number.enumerated() {
            if character.isASCII, character.isNumber { dialed.append(character) } else if index == 0, character == "+" { dialed.append(character) }
        }
        guard dialed.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel:\(dialed)")
    }

    /// The icon of the type of the item `target` names.
    @MainActor
    static func typeIcon(of target: ItemID, in library: any ItemLibrary) -> String? {
        library.headerItem(target).flatMap { library.catalogue.icon(for: $0.type) }
    }

    @MainActor
    private static func isPerson(_ target: ItemID, in library: any ItemLibrary) -> Bool {
        library.headerItem(target).map { PageHeaderKind.of($0.type, in: library.catalogue) == .person } ?? false
    }

    /// A catalogue's words, looked up in the String Catalog as SwiftUI's text would look them up.
    static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
