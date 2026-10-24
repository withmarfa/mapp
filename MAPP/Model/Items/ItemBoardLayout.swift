import Foundation

nonisolated struct ItemBoardField: Identifiable, Hashable, Sendable {
    let key: String
    let label: String
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
        case .choice, .text: !field.options.isEmpty
        default: false
        }
    }

    static func availableFields(items: [Item], catalogue: Catalogue) -> [ItemBoardField] {
        var seen: Set<String> = []
        var result: [ItemBoardField] = []
        for type in Set(items.map(\.type)).sorted(by: { $0.rawValue < $1.rawValue }) {
            for field in eligibleFields(of: type, catalogue: catalogue) {
                guard seen.insert(field.key).inserted else { continue }
                result.append(ItemBoardField(key: field.key, label: field.displayLabel))
            }
        }
        return result.filter { $0.key == "status" } + result.filter { $0.key != "status" }
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
        if case .choice = field.kind, !field.options.contains(text) { return .invalid }
        return .option(text)
    }

    static func lanes(items: [Item], key: String, catalogue: Catalogue) -> [ItemBoardLane] {
        var values: [String] = []
        var seen: Set<String> = []
        for type in Set(items.map(\.type)).sorted(by: { $0.rawValue < $1.rawValue }) {
            for field in eligibleFields(of: type, catalogue: catalogue) where field.key == key {
                values += field.options.filter { !$0.isEmpty && seen.insert($0).inserted }
            }
        }
        let groups = Dictionary(grouping: items) { lane(for: $0, key: key, catalogue: catalogue) }
        let extra = groups.keys.compactMap { lane -> String? in
            if case .option(let value) = lane, !seen.contains(value) { return value }
            return nil
        }.sorted()
        var lanes = (values + extra).map { value in
            ItemBoardLane(id: .option(value), title: ItemTypeInfo.Field.label(ofOption: value), items: [])
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
            if case .choice = field.kind, !field.options.contains(option) { return .refused }
            value = .string(option)
        case .missing:
            guard !field.required else { return .refused }
            value = nil
        case .invalid, .notApplicable: return .refused
        }
        if item.value(of: key) == value { return .unchanged }
        return .set(value)
    }
}
