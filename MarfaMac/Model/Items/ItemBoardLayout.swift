import Foundation

nonisolated struct ItemBoardLane: Identifiable, Hashable, Sendable {
    enum ID: Hashable, Sendable {
        case option(String), group(StatusGroup), missing, invalid, notApplicable
        /// A group of any other grouping, by its key (`GroupKey`): a date's span, Set, a type, a parent.
        case key(String)
    }

    let id: ID
    let title: String
    /// The lane's key as a view's `group.order` and `group.hidden` name it (`GroupKey`).
    var groupKey: String {
        switch id {
        case .option(let word): word
        case .group(let group): group.rawValue
        case .missing: isNotSet ? GroupKey.notSet : GroupKey.none
        case .invalid: "\u{1}invalid"
        case .notApplicable: GroupKey.notApplicable
        case .key(let key): key
        }
    }

    /// The status mark its header carries, on a board of a status field or of status groups.
    var symbol: StatusSymbol?
    var items: [Item]
    /// Whether a card can be dropped here. A lane of a board that mixes status fields takes a card only where every
    /// type has a word in the group, and never the lane of items with no status.
    var takesItems = true
    /// Whether it is Set or Not Set's Not Set, which a card dropped in clears its field for.
    var isNotSet = false
}

/// A board is a projection of the current library, never a second store of its items.
nonisolated enum ItemBoardLayout {
    /// The catalogue has already resolved inheritance, including a child's requiredness overrides.
    static func eligibleFields(of type: TypeID, catalogue: Catalogue) -> [ItemTypeInfo.Field] {
        guard let info = catalogue.itemTypes[type] else { return [] }
        return info.fields.filter {
            // Setters also treat the literal "title" key as the item's title.
            $0.key != "title" && $0.key != info.titleKey && $0.key != info.bodyKey && isCompatible($0)
        }
    }

    static func isCompatible(_ field: ItemTypeInfo.Field) -> Bool {
        switch field.kind {
        case .choice, .status: !field.options.isEmpty
        default: false
        }
    }

    static func field(_ key: String, of item: Item, catalogue: Catalogue) -> ItemTypeInfo.Field? {
        eligibleFields(of: item.type, catalogue: catalogue).first { $0.key == key }
    }

    /// The first status field of an item's type: the one a board of mixed status fields sorts the item by.
    static func statusField(of item: Item, catalogue: Catalogue) -> ItemTypeInfo.Field? {
        eligibleFields(of: item.type, catalogue: catalogue).first(where: \.isStatus)
    }

    /// The key whose value puts an item in the Invalid Value lane: its own status field where the board sorts by
    /// status groups, `key` otherwise.
    static func invalidValueKey(of item: Item, key: String, groupsByStatus: Bool, catalogue: Catalogue) -> String {
        guard groupsByStatus else { return key }
        return statusField(of: item, catalogue: catalogue)?.key ?? key
    }

    private static func groupedLane(for item: Item, catalogue: Catalogue) -> ItemBoardLane.ID {
        // A type with no status is the lane of items with none.
        guard let field = statusField(of: item, catalogue: catalogue) else { return .missing }
        guard let value = item.value(of: field.key), value != .null else { return .missing }
        guard case .string(let text) = value else { return .invalid }
        guard !text.isEmpty else { return .missing }
        return field.statusGroup(of: text).map(ItemBoardLane.ID.group) ?? .invalid
    }

    static func lane(for item: Item, key: String, catalogue: Catalogue) -> ItemBoardLane.ID {
        guard let field = field(key, of: item, catalogue: catalogue) else { return .notApplicable }
        guard let value = item.value(of: key), value != .null else { return .missing }
        guard case .string(let text) = value else { return .invalid }
        guard !text.isEmpty else { return .missing }
        if !field.options.contains(text) { return .invalid }
        return .option(text)
    }

    /// The lanes of a board by `key`: the words the items' types declare, a status field's by their group (as the
    /// table lists them) and then in declared order, then No Value, and Invalid Value and Not Applicable where an
    /// item needs them. A board's fields are closed, so a word no type declares is an invalid value. Where the types
    /// keep their status in different fields, or the person groups by them (`statusGroups`), the lanes are Marfa's
    /// status groups instead. Within a lane the cards follow `order`, each item's place in the sort the window shows, or
    /// the title where nothing sorts them. With `asMarfa`, as a saved view groups, status groups put a word no group
    /// claims in No Status, as Marfa does (`device/view-group-status`).
    static func lanes(
        items: [Item], key: String, catalogue: Catalogue, order: [ItemID: Int]? = nil, statusGroups: Bool = false, asMarfa: Bool = false
    ) -> [ItemBoardLane] {
        if statusGroups { return groupLanes(items: items, catalogue: catalogue, order: order, asMarfa: asMarfa) }
        var values: [(word: String, bucket: StatusBucket)] = []
        var isStatus = false
        var seen: Set<String> = []
        for type in Set(items.map(\.type)).sorted(by: { $0.rawValue < $1.rawValue }) {
            for field in eligibleFields(of: type, catalogue: catalogue) where field.key == key {
                if field.isStatus { isStatus = true }
                for word in field.options where !word.isEmpty && seen.insert(word).inserted {
                    values.append((word, field.isStatus ? field.statusBucket(of: word) : .other))
                }
            }
        }
        // Words in one group, and the words of a choice, which has no groups, stay in declared order.
        values = values.enumerated().sorted { ($0.element.bucket.rank, $0.offset) < ($1.element.bucket.rank, $1.offset) }.map(\.element)
        let groups = Dictionary(grouping: items) { lane(for: $0, key: key, catalogue: catalogue) }
        var lanes = values.map { entry in
            ItemBoardLane(
                id: .option(entry.word), title: ItemTypeInfo.Field.label(ofOption: entry.word),
                symbol: isStatus ? StatusSymbol(group: statusGroup(of: entry.bucket)) : nil, items: [])
        }
        lanes.append(ItemBoardLane(id: .missing, title: String(localized: "No Value"), items: []))
        if groups[.invalid] != nil {
            lanes.append(ItemBoardLane(id: .invalid, title: String(localized: "Invalid Value"), items: []))
        }
        if groups[.notApplicable] != nil {
            lanes.append(ItemBoardLane(id: .notApplicable, title: String(localized: "Not Applicable"), items: []))
        }
        return lanes.map { lane in
            var lane = lane
            lane.items = sorted(groups[lane.id] ?? [], by: order)
            return lane
        }
    }

    /// The lanes of a board whose types keep their status in different fields: Marfa's four status groups, which
    /// every type shares, then No Status (which holds a type with no status too), and Invalid Value where an item needs it.
    private static func groupLanes(items: [Item], catalogue: Catalogue, order: [ItemID: Int]?, asMarfa: Bool) -> [ItemBoardLane] {
        let groups = Dictionary(grouping: items) { item in
            let lane = groupedLane(for: item, catalogue: catalogue)
            return asMarfa && lane == .invalid ? .missing : lane
        }
        let types = Set(items.map(\.type))
        let fields = types.compactMap { type in eligibleFields(of: type, catalogue: catalogue).first(where: \.isStatus) }
        var lanes = StatusGroup.allCases.map { group in
            ItemBoardLane(id: .group(group), title: StatusBucket.group(group).title, symbol: StatusSymbol(group: group), items: [],
                          takesItems: fields.allSatisfy { firstWord($0, in: group) != nil })
        }
        lanes.append(ItemBoardLane(id: .missing, title: String(localized: "No Status"), items: [], takesItems: false))
        if groups[.invalid] != nil {
            lanes.append(ItemBoardLane(id: .invalid, title: String(localized: "Invalid Value"), items: [], takesItems: false))
        }
        return lanes.map { lane in
            var lane = lane
            lane.items = sorted(groups[lane.id] ?? [], by: order)
            return lane
        }
    }

    private static func statusGroup(of bucket: StatusBucket) -> StatusGroup? {
        if case .group(let group) = bucket { group } else { nil }
    }

    /// The word a card takes on moving into `group`: the first its type declares there.
    private static func firstWord(_ field: ItemTypeInfo.Field, in group: StatusGroup) -> String? {
        field.options.first { !$0.isEmpty && field.statusGroup(of: $0) == group }
    }

    private static func sorted(_ items: [Item], by order: [ItemID: Int]?) -> [Item] {
        if let order {
            return items.sorted { (order[$0.id] ?? .max, $0.id.rawValue) < (order[$1.id] ?? .max, $1.id.rawValue) }
        }
        return items.sorted {
            let order = $0.displayTitle.localizedStandardCompare($1.displayTitle)
            return order == .orderedSame ? $0.id.rawValue < $1.id.rawValue : order == .orderedAscending
        }
    }

    /// The lanes of any other grouping, from its groups (`ItemTableLayout.groups`): only Not Set takes a card, which
    /// clears the field; a date's span, Set and the rest take none, since the app would have to invent a value.
    static func lanes(of groups: [ItemTableGroup], mode: GroupMode, order: [ItemID: Int]? = nil) -> [ItemBoardLane] {
        groups.map { group in
            let items = sorted(group.rows.map(\.item), by: order)
            switch group.id {
            case GroupKey.notApplicable:
                return ItemBoardLane(id: .notApplicable, title: group.title, items: items, takesItems: false)
            case GroupKey.notSet where mode == .presence:
                return ItemBoardLane(id: .missing, title: group.title, items: items, isNotSet: true)
            default:
                return ItemBoardLane(id: .key(group.id), title: group.title, items: items, takesItems: false)
            }
        }
    }

    /// The lanes in a view's or a place's order, less the hidden ones and, where Hide Empty Groups is on, the empty ones.
    static func arranged(_ lanes: [ItemBoardLane], order: [String]?, hidden: Set<String>?, hidesEmpty: Bool) -> [ItemBoardLane] {
        var arranged = lanes
        if let order, !order.isEmpty {
            let named = order.compactMap { key in lanes.first { $0.groupKey == key } }
            let keys = Set(named.map(\.groupKey))
            arranged = named + lanes.filter { !keys.contains($0.groupKey) }
        }
        let hidden = hidden ?? []
        return arranged.filter { !hidden.contains($0.groupKey) && !(hidesEmpty && $0.items.isEmpty) }
    }

    enum Move: Equatable, Sendable {
        case set(PropertyValue?), unchanged, refused
        /// The field must hold a value, so it can't be cleared.
        case needsValue
    }

    /// The destination belongs to the board, but permission and allowed choices belong to this item's type.
    static func move(_ item: Item, key: String, to destination: ItemBoardLane.ID, catalogue: Catalogue) -> Move {
        if case .group(let group) = destination { return move(item, toGroup: group, catalogue: catalogue).move }
        // Clearing suits any field the type declares, as Set or Not Set's Not Set does.
        if destination == .missing, item.obstacle(toField: key) == nil, let info = catalogue.itemTypes[item.type],
           key != "title", key != info.titleKey, key != info.bodyKey, let declared = info.fields.first(where: { $0.key == key }) {
            guard !declared.required else { return .needsValue }
            return item.value(of: key) == nil ? .unchanged : .set(nil)
        }
        guard item.obstacle(toField: key) == nil, let field = field(key, of: item, catalogue: catalogue) else { return .refused }
        let value: PropertyValue?
        switch destination {
        case .option(let option):
            guard !option.isEmpty else { return .refused }
            if !field.options.contains(option) { return .refused }
            value = .string(option)
        case .group, .invalid, .notApplicable, .key, .missing: return .refused
        }
        if item.value(of: key) == value { return .unchanged }
        return .set(value)
    }

    /// A move into a status group writes the item's own status field, the first word its type declares in the group.
    static func move(_ item: Item, toGroup group: StatusGroup, catalogue: Catalogue) -> (key: String, move: Move) {
        guard let field = statusField(of: item, catalogue: catalogue), item.obstacle(toField: field.key) == nil else { return ("", .refused) }
        guard let word = firstWord(field, in: group) else { return (field.key, .refused) }
        if case .string(let current)? = item.value(of: field.key), field.statusGroup(of: current) == group { return (field.key, .unchanged) }
        return (field.key, .set(.string(word)))
    }

    /// What moving a selection to a lane changes, and why each item left out stays: gone from the library, not on
    /// the board now, in the bin or unable to be changed, a file, or a type that doesn't take the lane. An item
    /// already in the lane is no skip.
    struct MovePlan {
        var changes: [(id: ItemID, key: String, value: PropertyValue?)] = []
        var skips = BatchSkips()
    }

    @MainActor static func movePlan(
        _ ids: some Collection<ItemID>, key: String, to lane: ItemBoardLane.ID, shown: Set<ItemID>, in library: any ItemLibrary
    ) -> MovePlan {
        var plan = MovePlan()
        for id in Set(ids).sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let item = library.item(id) else {
                plan.skips.skip(.gone)
                continue
            }
            guard shown.contains(id) else {
                plan.skips.skip(.notShown)
                continue
            }
            var writeKey = key
            let outcome: Move
            if case .group(let group) = lane {
                let grouped = move(item, toGroup: group, catalogue: library.catalogue)
                writeKey = grouped.key
                outcome = grouped.move
            } else {
                outcome = move(item, key: key, to: lane, catalogue: library.catalogue)
            }
            switch outcome {
            case .set(let value): plan.changes.append((id, writeKey, value))
            case .unchanged: break
            case .refused: plan.skips.skip(item.obstacle(toField: writeKey) ?? (item.isFile ? .fileHasNoLane : .cantMoveToLane))
            case .needsValue: plan.skips.skip(item.obstacle(toField: writeKey) ?? .needsValue)
            }
        }
        return plan
    }
}
