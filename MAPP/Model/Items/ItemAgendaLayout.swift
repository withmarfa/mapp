import Foundation

nonisolated struct ItemAgendaRow: Identifiable, Hashable, Sendable {
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

nonisolated struct ItemAgendaGroup: Identifiable, Hashable, Sendable {
    enum ID: Hashable, Sendable {
        case day(Date), missing, invalid, notApplicable
    }

    let id: ID
    let rows: [ItemAgendaRow]
}

nonisolated enum ItemAgendaLayout {
    static func fields(for items: [Item], catalogue: Catalogue) -> [ItemTypeInfo.Field] {
        fields(forTypes: Set(items.map(\.type)), catalogue: catalogue)
    }

    static func fields(forTypes types: Set<TypeID>, catalogue: Catalogue) -> [ItemTypeInfo.Field] {
        var fields: [String: ItemTypeInfo.Field] = [:]
        for type in types.sorted(by: { $0.rawValue < $1.rawValue }) {
            for field in catalogue.itemTypes[type]?.fields ?? [] where field.kind.isDate {
                if fields[field.key] == nil { fields[field.key] = field }
            }
        }
        return fields.values.sorted {
            let comparison = $0.displayLabel.localizedStandardCompare($1.displayLabel)
            return comparison == .orderedSame ? $0.key < $1.key : comparison == .orderedAscending
        }
    }

    static func selectedField(_ selected: String?, fields: [ItemTypeInfo.Field]) -> String? {
        if let selected, fields.contains(where: { $0.key == selected }) { return selected }
        return ["due_at", "starts_at"].first { key in fields.contains { $0.key == key } } ?? fields.first?.key
    }

    static func groups(
        for items: [Item], field: String?, catalogue: Catalogue, calendar: Calendar = .current
    ) -> [ItemAgendaGroup] {
        var groups: [ItemAgendaGroup.ID: [ItemAgendaRow]] = [:]
        for item in items {
            let value = value(of: item, field: field, catalogue: catalogue, calendar: calendar)
            let id: ItemAgendaGroup.ID = switch value {
            case .dated(let date, _, _): .day(calendar.startOfDay(for: date))
            case .missing: .missing
            case .invalid: .invalid
            case .notApplicable: .notApplicable
            }
            groups[id, default: []].append(ItemAgendaRow(item: item, value: value))
        }
        let days = groups.keys.compactMap { id -> Date? in
            if case .day(let date) = id { return date }
            return nil
        }.sorted().map(ItemAgendaGroup.ID.day)
        return (days + [.missing, .invalid, .notApplicable]).compactMap { id in
            groups[id].map { ItemAgendaGroup(id: id, rows: $0.sorted(by: precedes)) }
        }
    }

    static func value(
        of item: Item, field: String?, catalogue: Catalogue, calendar: Calendar = .current
    ) -> ItemAgendaRow.Value {
        guard let field, catalogue.itemTypes[item.type]?.fields.contains(where: { $0.key == field && $0.kind.isDate }) == true
        else { return .notApplicable }
        guard let value = item.value(of: field), value != .null, value != .string("") else { return .missing }
        guard let text = value.string, let parsed = ItemDate.parse(text, calendar: calendar) else {
            return .invalid(ItemValueText.string(value))
        }
        return .dated(parsed.date, dateOnly: !parsed.hasTime, raw: text)
    }

    private static func precedes(_ lhs: ItemAgendaRow, _ rhs: ItemAgendaRow) -> Bool {
        if case .dated(let left, _, _) = lhs.value, case .dated(let right, _, _) = rhs.value, left != right {
            return left < right
        }
        let title = lhs.item.title.localizedStandardCompare(rhs.item.title)
        return title == .orderedSame ? lhs.id.rawValue < rhs.id.rawValue : title == .orderedAscending
    }
}
