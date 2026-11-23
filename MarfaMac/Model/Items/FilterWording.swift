import Foundation

/// A filter as a sentence: "Starts is set", "Due is before 30 Nov 2026", "Assignees include Rui Alves", "Due is in the last
/// 7 days". The row's chips draw it in three parts, the field, the operator and the values.
nonisolated enum FilterWording {
    /// How a chip reads, in the three parts it draws.
    struct Parts: Hashable, Sendable {
        var field: String
        var relation: String
        var values: String

        var sentence: String { [field, relation, values].filter { !$0.isEmpty }.joined(separator: " ") }
    }

    /// `titles` names an item by its identifier, which a parent or a collection is held by.
    static func parts(of clause: FilterClause, target: FilterTarget, calendar: Calendar, titles: (String) -> String? = { _ in nil }) -> Parts {
        Parts(field: target.label, relation: clause.op.word(for: target.kind), values: values(of: clause, target: target, calendar: calendar, titles: titles))
    }

    static func sentence(of clause: FilterClause, target: FilterTarget, calendar: Calendar, titles: (String) -> String? = { _ in nil }) -> String {
        parts(of: clause, target: target, calendar: calendar, titles: titles).sentence
    }

    static func values(of clause: FilterClause, target: FilterTarget, calendar: Calendar, titles: (String) -> String? = { _ in nil }) -> String {
        switch clause.op {
        case .isSet, .isEmpty, .beforeToday, .afterToday: return ""
        case .on, .before, .after: return clause.values.first.map { day($0, calendar: calendar) } ?? ""
        case .between:
            guard clause.values.count == 2 else { return "" }
            return String(localized: "\(day(clause.values[0], calendar: calendar)) and \(day(clause.values[1], calendar: calendar))")
        case .inLast, .inNext:
            guard let count = clause.values.first.flatMap({ Int($0) }) else { return "" }
            return days(count)
        case .equal, .notEqual, .less, .lessOrEqual, .greater, .greaterOrEqual, .contains, .startsWith:
            return clause.values.first ?? ""
        case .is, .isNot, .includes:
            return clause.values.map { value($0, target: target, titles: titles) }.joined(separator: ", ")
        }
    }

    private static func value(_ value: String, target: FilterTarget, titles: (String) -> String?) -> String {
        if value.isEmpty { return String(localized: "No Value") }
        switch target.kind {
        case .status:
            if let group = FilterClause.group(of: value) { return StatusBucket.group(group).title }
            return ItemTypeInfo.Field.label(ofOption: value)
        case .choice: return ItemTypeInfo.Field.label(ofOption: value)
        case .boolean: return value == "true" ? String(localized: "Yes") : String(localized: "No")
        case .parent, .collection, .type: return titles(value) ?? value
        default: return value
        }
    }

    /// A relative filter as the row's note quotes it: "in the last 7 days", "before today".
    static func relativePhrase(of clause: FilterClause, calendar: Calendar) -> String {
        let count = clause.values.first.flatMap { Int($0) } ?? 0
        switch clause.op {
        case .beforeToday: return String(localized: "before today")
        case .afterToday: return String(localized: "after today")
        case .inLast: return count == 1 ? String(localized: "in the last day") : String(localized: "in the last \(count) days")
        case .inNext: return count == 1 ? String(localized: "in the next day") : String(localized: "in the next \(count) days")
        default: return ""
        }
    }

    private static func days(_ count: Int) -> String {
        count == 1 ? String(localized: "1 day") : String(localized: "\(count) days")
    }

    static func day(_ text: String, calendar: Calendar) -> String {
        guard let date = FilterDays.start(of: text, calendar: calendar) else { return text }
        var style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated).year()
        style.locale = calendar.locale ?? .current
        return date.formatted(style)
    }
}
