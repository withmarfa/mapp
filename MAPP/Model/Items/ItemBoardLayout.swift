import Foundation

nonisolated struct ItemBoardField: Identifiable, Hashable, Sendable {
    let key: String
    let label: String
    /// Whether the field is a status field, which a board offers first.
    var isStatus = false
    var id: String { key }
}

nonisolated struct ItemBoardLane: Identifiable, Hashable, Sendable {
    enum ID: Hashable, Sendable {
        case option(String), group(StatusGroup), missing, invalid, notApplicable
    }

    let id: ID
    let title: String
    var items: [Item]
    /// Whether a card can be dropped here. A lane of a board that mixes status fields takes a card only where every
    /// type has a word in the group, and never the lane of items with no status.
    var takesItems = true
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

    static func availableFields(items: [Item], catalogue: Catalogue) -> [ItemBoardField] {
        Cost.measure(.boardFields) { availableFieldsUnmeasured(items: items, catalogue: catalogue) }
    }

    private static func availableFieldsUnmeasured(items: [Item], catalogue: Catalogue) -> [ItemBoardField] {
        var seen: Set<String> = []
        var result: [ItemBoardField] = []
        for type in Set(items.map(\.type)).sorted(by: { $0.rawValue < $1.rawValue }) {
            for field in eligibleFields(of: type, catalogue: catalogue) {
                guard seen.insert(field.key).inserted else { continue }
                result.append(ItemBoardField(key: field.key, label: field.label, isStatus: field.isStatus))
            }
        }
        return result.filter(\.isStatus) + result.filter { !$0.isStatus }
    }

    static func selectedField(_ preferred: String?, available: [ItemBoardField]) -> ItemBoardField? {
        available.first { $0.key == preferred } ?? available.first
    }

    static func field(_ key: String, of item: Item, catalogue: Catalogue) -> ItemTypeInfo.Field? {
        eligibleFields(of: item.type, catalogue: catalogue).first { $0.key == key }
    }

    /// The first status field of an item's type: the one a board of mixed status fields sorts the item by.
    static func statusField(of item: Item, catalogue: Catalogue) -> ItemTypeInfo.Field? {
        eligibleFields(of: item.type, catalogue: catalogue).first(where: \.isStatus)
    }

    /// Whether the board of `items` sorts by `key`'s status groups: the items' types have status fields of more than
    /// one key, so no one field's words can be every card's lane. One shared field keeps its own words.
    static func groupsByStatus(items: [Item], key: String, catalogue: Catalogue) -> Bool {
        var keys: Set<String> = []
        for type in Set(items.map(\.type)) {
            if let field = eligibleFields(of: type, catalogue: catalogue).first(where: \.isStatus) { keys.insert(field.key) }
        }
        return keys.count > 1 && keys.contains(key)
    }

    private static func groupedLane(for item: Item, catalogue: Catalogue) -> ItemBoardLane.ID {
        guard let field = statusField(of: item, catalogue: catalogue) else { return .notApplicable }
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
    /// keep their status in different fields (`groupsByStatus`), the lanes are Marfa's status groups instead.
    static func lanes(items: [Item], key: String, catalogue: Catalogue) -> [ItemBoardLane] {
        if groupsByStatus(items: items, key: key, catalogue: catalogue) { return groupLanes(items: items, catalogue: catalogue) }
        var values: [(word: String, bucket: StatusBucket)] = []
        var seen: Set<String> = []
        for type in Set(items.map(\.type)).sorted(by: { $0.rawValue < $1.rawValue }) {
            for field in eligibleFields(of: type, catalogue: catalogue) where field.key == key {
                for word in field.options where !word.isEmpty && seen.insert(word).inserted {
                    values.append((word, field.isStatus ? field.statusBucket(of: word) : .other))
                }
            }
        }
        // Words in one group, and the words of a choice, which has no groups, stay in declared order.
        values = values.enumerated().sorted { ($0.element.bucket.rank, $0.offset) < ($1.element.bucket.rank, $1.offset) }.map(\.element)
        let groups = Dictionary(grouping: items) { lane(for: $0, key: key, catalogue: catalogue) }
        var lanes = values.map { entry in
            ItemBoardLane(id: .option(entry.word), title: ItemTypeInfo.Field.label(ofOption: entry.word), items: [])
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
            lane.items = sorted(groups[lane.id] ?? [])
            return lane
        }
    }

    /// The lanes of a board whose types keep their status in different fields: Marfa's four status groups, which
    /// every type shares, then No Status, and Invalid Value and Not Applicable where an item needs them.
    private static func groupLanes(items: [Item], catalogue: Catalogue) -> [ItemBoardLane] {
        let groups = Dictionary(grouping: items) { groupedLane(for: $0, catalogue: catalogue) }
        let types = Set(items.map(\.type))
        let fields = types.compactMap { type in eligibleFields(of: type, catalogue: catalogue).first(where: \.isStatus) }
        var lanes = StatusGroup.allCases.map { group in
            var lane = ItemBoardLane(id: .group(group), title: StatusBucket.group(group).title, items: [])
            lane.takesItems = fields.allSatisfy { firstWord($0, in: group) != nil }
            return lane
        }
        var missing = ItemBoardLane(id: .missing, title: String(localized: "No Status"), items: [])
        missing.takesItems = false
        lanes.append(missing)
        if groups[.invalid] != nil {
            var lane = ItemBoardLane(id: .invalid, title: String(localized: "Invalid Value"), items: [])
            lane.takesItems = false
            lanes.append(lane)
        }
        if groups[.notApplicable] != nil {
            var lane = ItemBoardLane(id: .notApplicable, title: String(localized: "Not Applicable"), items: [])
            lane.takesItems = false
            lanes.append(lane)
        }
        return lanes.map { lane in
            var lane = lane
            lane.items = sorted(groups[lane.id] ?? [])
            return lane
        }
    }

    /// The word a card takes on moving into `group`: the first its type declares there.
    private static func firstWord(_ field: ItemTypeInfo.Field, in group: StatusGroup) -> String? {
        field.options.first { !$0.isEmpty && field.statusGroup(of: $0) == group }
    }

    private static func sorted(_ items: [Item]) -> [Item] {
        items.sorted {
            let order = $0.displayTitle.localizedStandardCompare($1.displayTitle)
            return order == .orderedSame ? $0.id.rawValue < $1.id.rawValue : order == .orderedAscending
        }
    }

    enum Move: Equatable, Sendable {
        case set(PropertyValue?), unchanged, refused
    }

    /// The destination belongs to the board, but permission and allowed choices belong to this item's type.
    static func move(_ item: Item, key: String, to destination: ItemBoardLane.ID, catalogue: Catalogue) -> Move {
        if case .group(let group) = destination { return move(item, toGroup: group, catalogue: catalogue).move }
        guard item.isEditable, let field = field(key, of: item, catalogue: catalogue) else { return .refused }
        let value: PropertyValue?
        switch destination {
        case .option(let option):
            guard !option.isEmpty else { return .refused }
            if !field.options.contains(option) { return .refused }
            value = .string(option)
        case .missing:
            guard !field.required else { return .refused }
            value = nil
        case .group, .invalid, .notApplicable: return .refused
        }
        if item.value(of: key) == value { return .unchanged }
        return .set(value)
    }

    /// A move into a status group writes the item's own status field, the first word its type declares in the group.
    static func move(_ item: Item, toGroup group: StatusGroup, catalogue: Catalogue) -> (key: String, move: Move) {
        guard item.isEditable, let field = statusField(of: item, catalogue: catalogue) else { return ("", .refused) }
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
            case .refused: plan.skips.skip(item.writeObstacle ?? (item.isFile ? .fileHasNoLane : .cantMoveToLane))
            }
        }
        return plan
    }
}
