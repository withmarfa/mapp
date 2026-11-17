import Foundation
import Marfa

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
            let comparison = $0.label.localizedStandardCompare($1.label)
            return comparison == .orderedSame ? $0.key < $1.key : comparison == .orderedAscending
        }
    }

    /// The field the person pointed the timeline at, or nil where each item sits on the date its type's look names
    /// (`ItemPlacement`).
    static func selectedField(_ selected: String?, fields: [ItemTypeInfo.Field]) -> String? {
        guard let selected, fields.contains(where: { $0.key == selected }) else { return nil }
        return selected
    }

    /// The days of the items, from `today` on first and then the days before it, the latest first, so the timeline
    /// opens on today's agenda; an item with no date, or an invalid one, follows. Inside a day a whole-day item leads,
    /// then the rest by time.
    static func groups(
        for items: [Item], field: String?, looks: [TypeID: TypeLook], catalogue: Catalogue, today: Date? = nil,
        calendar: Calendar = .current
    ) -> [ItemTimelineGroup] {
        var groups: [ItemTimelineGroup.ID: [ItemTimelineRow]] = [:]
        for item in items {
            let value = value(of: item, look: looks[item.type] ?? .empty, field: field, catalogue: catalogue, calendar: calendar)
            let id: ItemTimelineGroup.ID = switch value {
            case .dated(let date, _, _): .day(calendar.startOfDay(for: date))
            case .missing: .missing
            case .invalid: .invalid
            case .notApplicable: .notApplicable
            }
            groups[id, default: []].append(ItemTimelineRow(item: item, value: value))
        }
        let start = calendar.startOfDay(for: today ?? .now)
        let days = groups.keys.compactMap { id -> Date? in
            if case .day(let date) = id { return date }
            return nil
        }
        let ahead = days.filter { $0 >= start }.sorted()
        let behind = days.filter { $0 < start }.sorted(by: >)
        return ((ahead + behind).map(ItemTimelineGroup.ID.day) + [.missing, .invalid, .notApplicable]).compactMap { id in
            groups[id].map { ItemTimelineGroup(id: id, rows: $0.sorted(by: precedes)) }
        }
    }

    static func value(
        of item: Item, look: TypeLook, field: String?, catalogue: Catalogue, calendar: Calendar = .current
    ) -> ItemTimelineRow.Value {
        switch ItemPlacement.of(item, look: look, field: field, catalogue: catalogue, calendar: calendar) {
        case .placed(let placement): .dated(placement.start, dateOnly: !placement.hasTime, raw: placement.raw)
        case .missing: .missing
        case .invalid(let raw): .invalid(raw)
        case .notApplicable: .notApplicable
        }
    }

    /// Where today's line of the present moment sits among a day's rows: before the first timed row that is still to
    /// come, or after the last. Nil for a day that is not today, or one with no timed row.
    static func nowLine(in group: ItemTimelineGroup, now: Date, calendar: Calendar = .current) -> Int? {
        guard case .day(let day) = group.id, day == calendar.startOfDay(for: now) else { return nil }
        guard group.rows.contains(where: { if case .dated(_, false, _) = $0.value { true } else { false } }) else { return nil }
        let coming = group.rows.firstIndex { row in
            if case .dated(let date, false, _) = row.value { return date > now }
            return false
        }
        return coming ?? group.rows.count
    }

    private static func precedes(_ lhs: ItemTimelineRow, _ rhs: ItemTimelineRow) -> Bool {
        if case .dated(let left, let leftDay, _) = lhs.value, case .dated(let right, let rightDay, _) = rhs.value {
            if leftDay != rightDay { return leftDay }
            if left != right { return left < right }
        }
        let title = lhs.item.displayTitle.localizedStandardCompare(rhs.item.displayTitle)
        return title == .orderedSame ? lhs.id.rawValue < rhs.id.rawValue : title == .orderedAscending
    }
}
