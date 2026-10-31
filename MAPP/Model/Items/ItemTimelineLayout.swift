import Foundation

nonisolated struct ItemTimelineRow: Identifiable, Hashable, Sendable {
    enum Value: Hashable, Sendable {
        case dated(Date, dateOnly: Bool, raw: String)
        case missing
        case invalid(String)
        case notApplicable
    }

    let item: Item
    let value: Value
    var id: ItemID { item.id }
}

nonisolated struct ItemTimelineGroup: Identifiable, Hashable, Sendable {
    enum ID: Hashable, Sendable {
        case day(Date), missing, invalid, notApplicable
    }

    let id: ID
    let rows: [ItemTimelineRow]
}

nonisolated enum ItemTimelineLayout {
    static func fields(for items: [Item], catalogue: Catalogue) -> [ItemTypeInfo.Field] {
        Cost.measure(.timelineFields) { fields(forTypes: Set(items.map(\.type)), catalogue: catalogue) }
    }

    /// The date fields of `types`, a task's due date first (it is what a timeline of tasks is for), then an event's
    /// start, then the rest by label.
    static func fields(forTypes types: Set<TypeID>, catalogue: Catalogue) -> [ItemTypeInfo.Field] {
        var fields: [String: ItemTypeInfo.Field] = [:]
        var dueDates: Set<String> = []
        for type in types.sorted(by: { $0.rawValue < $1.rawValue }) {
            for field in catalogue.itemTypes[type]?.fields ?? [] where field.kind.isDate {
                if fields[field.key] == nil { fields[field.key] = field }
                if catalogue.isDueDate(field, of: type) { dueDates.insert(field.key) }
            }
        }
        func lead(_ key: String) -> Int { dueDates.contains(key) ? 0 : key == "starts_at" ? 1 : 2 }
        return fields.values.sorted {
            let (x, y) = (lead($0.key), lead($1.key))
            if x != y { return x < y }
            let comparison = $0.displayLabel.localizedStandardCompare($1.displayLabel)
            return comparison == .orderedSame ? $0.key < $1.key : comparison == .orderedAscending
        }
    }

    static func selectedField(_ selected: String?, fields: [ItemTypeInfo.Field]) -> String? {
        if let selected, fields.contains(where: { $0.key == selected }) { return selected }
        return fields.first?.key
    }

    static func groups(
        for items: [Item], field: String?, catalogue: Catalogue, calendar: Calendar = .current
    ) -> [ItemTimelineGroup] {
        var groups: [ItemTimelineGroup.ID: [ItemTimelineRow]] = [:]
        for item in items {
            let value = value(of: item, field: field, catalogue: catalogue, calendar: calendar)
            let id: ItemTimelineGroup.ID = switch value {
            case .dated(let date, _, _): .day(calendar.startOfDay(for: date))
            case .missing: .missing
            case .invalid: .invalid
            case .notApplicable: .notApplicable
            }
            groups[id, default: []].append(ItemTimelineRow(item: item, value: value))
        }
        let days = groups.keys.compactMap { id -> Date? in
            if case .day(let date) = id { return date }
            return nil
        }.sorted().map(ItemTimelineGroup.ID.day)
        return (days + [.missing, .invalid, .notApplicable]).compactMap { id in
            groups[id].map { ItemTimelineGroup(id: id, rows: $0.sorted(by: precedes)) }
        }
    }

    static func value(
        of item: Item, field: String?, catalogue: Catalogue, calendar: Calendar = .current
    ) -> ItemTimelineRow.Value {
        guard let field, catalogue.itemTypes[item.type]?.fields.contains(where: { $0.key == field && $0.kind.isDate }) == true
        else { return .notApplicable }
        guard let value = item.value(of: field), value != .null, value != .string("") else { return .missing }
        guard let text = value.string, let parsed = ItemDate.parse(text, calendar: calendar) else {
            return .invalid(ItemValueText.string(value))
        }
        return .dated(parsed.date, dateOnly: !parsed.hasTime, raw: text)
    }

    private static func precedes(_ lhs: ItemTimelineRow, _ rhs: ItemTimelineRow) -> Bool {
        if case .dated(let left, _, _) = lhs.value, case .dated(let right, _, _) = rhs.value, left != right {
            return left < right
        }
        let title = lhs.item.title.localizedStandardCompare(rhs.item.title)
        return title == .orderedSame ? lhs.id.rawValue < rhs.id.rawValue : title == .orderedAscending
    }
}
