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
        case option(String), missing, invalid, notApplicable
    }

    let id: ID
    let title: String
    var items: [Item]
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
                result.append(ItemBoardField(key: field.key, label: field.displayLabel, isStatus: field.isStatus))
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
    /// item needs them. A board's fields are closed, so a word no type declares is an invalid value.
    static func lanes(items: [Item], key: String, catalogue: Catalogue) -> [ItemBoardLane] {
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
            lane.items = (groups[lane.id] ?? []).sorted {
                let order = $0.title.localizedStandardCompare($1.title)
                return order == .orderedSame ? $0.id.rawValue < $1.id.rawValue : order == .orderedAscending
            }
            return lane
        }
    }

    enum Move: Equatable, Sendable {
        case set(PropertyValue?), unchanged, refused
    }

    /// The destination belongs to the board, but permission and allowed choices belong to this item's type.
    static func move(_ item: Item, key: String, to destination: ItemBoardLane.ID, catalogue: Catalogue) -> Move {
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
        case .invalid, .notApplicable: return .refused
        }
        if item.value(of: key) == value { return .unchanged }
        return .set(value)
    }

    /// What moving a selection to a lane changes, and why each item left out stays: gone from the library, not on
    /// the board now, in the bin or unable to be changed, a file, or a type that doesn't take the lane. An item
    /// already in the lane is no skip.
    struct MovePlan {
        var changes: [(id: ItemID, value: PropertyValue?)] = []
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
            switch move(item, key: key, to: lane, catalogue: library.catalogue) {
            case .set(let value): plan.changes.append((id, value))
            case .unchanged: break
            case .refused: plan.skips.skip(item.writeObstacle ?? (item.isFile ? .fileHasNoLane : .cantMoveToLane))
            }
        }
        return plan
    }
}
