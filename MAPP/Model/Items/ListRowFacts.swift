import Foundation
import Marfa

/// What a Task row says about a task, each fact only where the item has it, so a row with none leaves no gap. The
/// due date, priority, assignees and repeat are read from a task (`Catalogue.isTask`) as the table reads them; the
/// status is any type's status field, whatever its words.
nonisolated struct TaskRowFacts: Hashable, Sendable {
    struct Due: Hashable, Sendable {
        let label: String
        /// Due today or late, which the row tints.
        let isPressing: Bool
    }

    struct People: Hashable, Sendable {
        /// The first person's initials; nil where they have no letters.
        let initials: String?
        let label: String
    }

    var statusGroup: StatusGroup?
    var due: Due?
    /// The priority's value as the type declares it, which the row writes as a word and colors as the value panel does.
    var priority: String?
    var people: People?
    var repeats: String?
    /// When a finished task finished, in words: "Yesterday", "Canceled 15 Jun".
    var finish: String?

    var hasLine: Bool { due != nil || priority != nil || people != nil || repeats != nil || finish != nil }

    static func make(
        for item: Item, catalogue: Catalogue, now: Date, format: DateFormat, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> TaskRowFacts {
        var facts = TaskRowFacts()
        facts.statusGroup = catalogue.statusGroup(of: item)
        func text(_ key: String) -> String? {
            item.value(of: key)?.string.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        if let group = facts.statusGroup, group.isFinished {
            let day = text(completedField).flatMap { ItemDate.parse($0, calendar: calendar)?.date } ?? item.modified
            let when = DateDisplay.text(of: day, hasTime: false, place: .table, format: format, now: now, calendar: calendar, locale: locale)
            facts.finish = group == .canceled ? String(localized: "Canceled \(when)") : when
        }
        guard catalogue.isTask(item.type) else { return facts }
        if facts.finish == nil, let due = text(MarfaMapping.dueField).flatMap({ ItemDate.parse($0, calendar: calendar)?.date }) {
            facts.due = dueFact(due, now: now, format: format, calendar: calendar, locale: locale)
        }
        facts.priority = text(MarfaMapping.priorityField)
        facts.people = people(of: item)
        facts.repeats = item.value(of: recurrenceField).flatMap(repeatWords)
        return facts
    }

    private static let completedField = "completed_at"
    private static let recurrenceField = "recurrence"
    private static let assigneesField = "assignees"

    private static func dueFact(_ due: Date, now: Date, format: DateFormat, calendar: Calendar, locale: Locale) -> Due {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case ...(-2): return Due(label: String(localized: "\(-days) days late"), isPressing: true)
        case -1: return Due(label: String(localized: "1 day late"), isPressing: true)
        case 0: return Due(label: String(localized: "Due today"), isPressing: true)
        case 1: return Due(label: String(localized: "Due tomorrow"), isPressing: false)
        case 2...6:
            let day = due.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated))
            return Due(label: String(localized: "Due \(day)"), isPressing: false)
        default:
            let label = DateDisplay.text(of: due, hasTime: false, place: .table, format: format, now: now, calendar: calendar, locale: locale)
            return Due(label: label, isPressing: false)
        }
    }

    /// One person by name, with their initials; several as a count. An entry names a person by name, email or both.
    private static func people(of item: Item) -> People? {
        guard case .array(let entries)? = item.value(of: assigneesField) else { return nil }
        let names = entries.compactMap { entry -> String? in
            guard case .object(let members) = entry else { return nil }
            let name = members["name"]?.string?.trimmingCharacters(in: .whitespaces) ?? ""
            let email = members["email"]?.string?.trimmingCharacters(in: .whitespaces) ?? ""
            return !name.isEmpty ? name : (email.isEmpty ? nil : email)
        }
        guard let first = names.first else { return nil }
        let initials = PersonInitials.of(first)
        if names.count == 1 { return People(initials: initials, label: first) }
        return People(initials: initials, label: String(localized: "\(names.count) people"))
    }

    /// A repeat in a word: the frequency of its RRULE, with its interval where it is more than one. A rule with no
    /// frequency, such as dates listed one by one, is only said to repeat.
    static func repeatWords(_ value: PropertyValue) -> String? {
        guard case .array(let lines) = value, !lines.isEmpty else { return nil }
        let rule = lines.compactMap(\.string).first { $0.uppercased().hasPrefix("RRULE") }
        guard let rule else { return String(localized: "Repeats") }
        var parts: [String: String] = [:]
        for pair in rule.drop(while: { $0 != ":" }).dropFirst().split(separator: ";") {
            let halves = pair.split(separator: "=", maxSplits: 1)
            if halves.count == 2 { parts[halves[0].uppercased()] = halves[1].uppercased() }
        }
        let interval = parts["INTERVAL"].flatMap(Int.init) ?? 1
        switch (parts["FREQ"], interval > 1) {
        case ("DAILY", false): return String(localized: "Daily")
        case ("WEEKLY", false): return String(localized: "Weekly")
        case ("MONTHLY", false): return String(localized: "Monthly")
        case ("YEARLY", false): return String(localized: "Yearly")
        case ("DAILY", true): return String(localized: "Every \(interval) days")
        case ("WEEKLY", true): return String(localized: "Every \(interval) weeks")
        case ("MONTHLY", true): return String(localized: "Every \(interval) months")
        case ("YEARLY", true): return String(localized: "Every \(interval) years")
        default: return String(localized: "Repeats")
        }
    }
}

/// What a Highlight row says: the color of its rule, and where the passage came from.
nonisolated struct HighlightRowFacts: Hashable, Sendable {
    /// The `color` the highlight holds: one of Marfa's six names.
    var color: String?
    /// The item the passage is an excerpt of, by name.
    var source: String?
    /// Where in the source: "page 41", or "location 812" where the locator is a position.
    var place: String?

    /// The source and the place as one line, whichever of them there is.
    var line: String? {
        let parts = [source, place].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    @MainActor
    static func make(for item: Item, in library: any ItemLibrary) -> HighlightRowFacts {
        func text(_ key: String) -> String? {
            item.value(of: key)?.string.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        var facts = HighlightRowFacts()
        facts.color = text("color")
        for edge in item.edgesOut where edge.type == excerptEdge {
            if case .item(let id) = edge.target, let source = library.item(id) {
                facts.source = source.displayTitle
                break
            }
        }
        if let start = text("start_location") {
            switch text("locator_type") {
            case "page": facts.place = String(localized: "page \(start)")
            case "offset", "order": facts.place = String(localized: "location \(start)")
            case "time": facts.place = start
            default: break
            }
        }
        return facts
    }

    private static let excerptEdge = "excerpt-of"
}

/// What a Person row says under the name: the same line the person's page keeps under theirs, or the entity's own
/// description where there is no job.
nonisolated struct PersonRowFacts: Hashable, Sendable {
    var initials: String?
    var line: String?

    static func make(for item: Item) -> PersonRowFacts {
        let described = PersonHeader(item: item).subtitle
            ?? item.value(of: "description")?.string?.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isNewline).first.map(String.init)
        return PersonRowFacts(initials: PersonInitials.of(item.displayTitle), line: described?.isEmpty == true ? nil : described)
    }
}
