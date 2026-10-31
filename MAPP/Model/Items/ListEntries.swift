import Foundation

/// What a number field takes: whole numbers or any, and within its declared bounds. Marfa refuses a value outside them
/// (`types/range-refused`), so the app refuses it at input.
nonisolated struct NumberRule: Hashable, Sendable {
    var integer = false
    var minimum: Decimal?
    var maximum: Decimal?

    func allows(_ number: Decimal) -> Bool {
        if let minimum, number < minimum { return false }
        if let maximum, number > maximum { return false }
        guard integer else { return true }
        var rounded = Decimal()
        var source = number
        NSDecimalRound(&rounded, &source, 0, .plain)
        return rounded == number
    }

    /// Why `allows` refuses a number, in the words the person is told.
    var requirement: String? {
        switch (minimum, maximum, integer) {
        case (let low?, let high?, false): String(localized: "Enter a number from \(PropertyNumber.editing(low)) to \(PropertyNumber.editing(high)).")
        case (let low?, let high?, true): String(localized: "Enter a whole number from \(PropertyNumber.editing(low)) to \(PropertyNumber.editing(high)).")
        case (let low?, nil, false): String(localized: "Enter a number of \(PropertyNumber.editing(low)) or more.")
        case (let low?, nil, true): String(localized: "Enter a whole number of \(PropertyNumber.editing(low)) or more.")
        case (nil, let high?, false): String(localized: "Enter a number of \(PropertyNumber.editing(high)) or less.")
        case (nil, let high?, true): String(localized: "Enter a whole number of \(PropertyNumber.editing(high)) or less.")
        case (nil, nil, true): String(localized: "Enter a whole number.")
        case (nil, nil, false): nil
        }
    }
}

/// The shape of a list of entries: an `array` field of `object` that declares its members (`items_fields`). One
/// mechanism covers every such field, a person's `emails` and an event's `attendees` alike; nothing here names a field.
nonisolated struct ListShape: Hashable, Sendable {
    struct Member: Hashable, Sendable, Identifiable {
        enum Kind: Hashable, Sendable {
            case text(ItemTypeInfo.Field.TextFormat?)
            case choice([String])
            case number(NumberRule)
            case boolean
            case date(includesTime: Bool)
        }

        let key: String
        let kind: Kind
        var required = false
        var id: String { key }
        var label: String { ItemTypeInfo.Field.displayLabel(MarfaMapping.label(forField: key)) }

        /// Whether the value is a value of this member.
        func accepts(_ value: PropertyValue) -> Bool {
            switch (kind, value) {
            case (.text, .string): true
            case (.choice(let choices), .string(let text)): choices.contains(text)
            case (.number(let rule), .number(let number)): rule.allows(number)
            case (.boolean, .bool): true
            case (.date(let includesTime), .string(let text)): ItemDate.parse(text).map { includesTime || !$0.hasTime } == true
            default: false
            }
        }
    }

    /// The members, in the order the type declares them.
    let members: [Member]

    func member(_ key: String) -> Member? { members.first { $0.key == key } }

    /// Whether `entry` is an entry Marfa takes for this list: an object with at least one member, only members the
    /// list declares, a value each member takes, and every required member.
    func accepts(_ entry: PropertyValue) -> Bool { faults(in: [entry]) == 0 }

    /// Why `entry` cannot be written, or nil where it can: it has no member at all, holds a member the list does not
    /// declare, lacks a required member, or holds a value its member does not take. `ignoringMissingRequired` passes
    /// an entry whose only fault is a required member not yet filled in, as an entry being added is while the person
    /// works through it.
    func refusal(of entry: [String: PropertyValue], ignoringMissingRequired: Bool = false) -> String? {
        if entry.isEmpty { return ignoringMissingRequired ? nil : String(localized: "An entry needs at least one value.") }
        if let undeclared = entry.keys.sorted().first(where: { member($0) == nil }) {
            return String(localized: "“\(undeclared)” isn’t part of this list. Remove it to save the list.")
        }
        for member in members {
            guard let value = entry[member.key] else {
                if member.required, !ignoringMissingRequired { return String(localized: "\(member.label) is required.") }
                continue
            }
            if !member.accepts(value) {
                if case .number(let rule) = member.kind, let requirement = rule.requirement { return requirement }
                return String(localized: "\(member.label) isn’t a valid value.")
            }
        }
        return nil
    }

    /// How many faults the entries hold that Marfa refuses the whole list for (`types/array-entries-refused`): an
    /// entry that is not an object or is empty, a member the list does not declare, a value its member does not take,
    /// and a required member missing. Zero for a list Marfa takes.
    func faults(in entries: [PropertyValue]) -> Int {
        entries.reduce(0) { count, entry in
            guard let fields = ListEntries.object(entry) else { return count + 1 }
            var faults = (fields.isEmpty ? 1 : 0) + fields.keys.filter { member($0) == nil }.count
            for member in members {
                if let value = fields[member.key] { faults += member.accepts(value) ? 0 : 1 } else if member.required { faults += 1 }
            }
            return count + faults
        }
    }

    /// Why one stored entry cannot be written as it is, or nil where it can.
    func fault(of entry: PropertyValue) -> String? {
        guard let fields = ListEntries.object(entry) else { return String(localized: "This entry isn’t in a form this list takes. Remove it to save the list.") }
        return refusal(of: fields)
    }

    /// A member's value as an entry's summary shows it, or nil where it shows nothing.
    func text(of member: Member, in entry: [String: PropertyValue]) -> String? {
        guard let value = entry[member.key] else { return nil }
        let shown: String
        switch value {
        case .string(let string):
            if case .choice = member.kind { shown = ItemTypeInfo.Field.label(ofOption: string) } else { shown = string }
        case .number(let number): shown = PropertyNumber.editing(number)
        case .bool(let flag): shown = flag ? String(localized: "Yes") : String(localized: "No")
        default: return nil
        }
        let trimmed = shown.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The words that stand for an entry in a row or a table cell: its members' values in the order the type declares
    /// them. No member is treated apart by its name.
    func summary(of entry: [String: PropertyValue]) -> String {
        members.compactMap { text(of: $0, in: entry) }.joined(separator: ", ")
    }

    /// What a table cell holds: the main entry's summary, and how many more the list has ("ann@x.com +2").
    func display(of value: PropertyValue) -> String {
        let entries = ListEntries.entries(of: value)
        guard let main = entries.first.flatMap(ListEntries.object) else { return ItemValueText.string(value) }
        let head = summary(of: main)
        return entries.count > 1 ? head + " +\(entries.count - 1)" : head
    }

    /// How a page row shows an entry: its first member that holds a value, as a link where that member is an email
    /// or web address, else the whole summary as text. Nil where the entry has nothing to show.
    func rowValue(of entry: [String: PropertyValue]) -> PropertyRow.Value? {
        let summary = summary(of: entry)
        guard !summary.isEmpty else { return nil }
        if let first = members.first(where: { text(of: $0, in: entry) != nil }), case .text(let format?) = first.kind,
           let text = text(of: first, in: entry) {
            return format == .email ? .email(text) : .url(text)
        }
        return .text(summary)
    }

    /// The number to call an entry holds, or nil. Marfa declares no phone format, so this reads the definition: only
    /// a list whose first declared member is required plain text (an entry is that value first, labelled after) can
    /// hold one, and only that member's own text is read. A list whose members are all optional, such as an address,
    /// never does, whatever its postcode looks like. A `phone` format in Marfa would settle this.
    func numberToCall(in entry: [String: PropertyValue]) -> String? {
        guard let first = members.first, first.required, case .text(nil) = first.kind,
              let text = entry[first.key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              Self.isDialable(text) else { return nil }
        return text
    }

    /// Whether the text is a telephone number as people write one: digits, with a leading plus, spaces, brackets,
    /// dots and dashes between them, and at least five digits.
    static func isDialable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.filter(\.isNumber).count >= 5, let first = trimmed.first, first == "+" || first == "(" || first.isNumber else { return false }
        return trimmed.allSatisfy { $0.isNumber || " +()-.".contains($0) }
    }

    /// The text a member of an entry is edited as.
    static func editing(_ value: PropertyValue?) -> String { value.map(ItemValueText.editing) ?? "" }
}

/// Editing a list of entries as a whole. The first entry is the main one (`types/entity-main-entry`). Every operation
/// returns the whole list with the entries it did not touch exactly as they were: an edit to one member never drops or
/// reorders another entry, and an entry the app cannot read (not an object) is carried along untouched.
nonisolated enum ListEntries {
    typealias Entry = [String: PropertyValue]

    /// The entries the value holds, each as an object where it is one.
    static func entries(of value: PropertyValue?) -> [PropertyValue] {
        guard case .array(let entries) = value else { return [] }
        return entries
    }

    static func object(_ entry: PropertyValue) -> Entry? {
        if case .object(let fields) = entry { fields } else { nil }
    }

    /// The main entry: the first one.
    static func main(of value: PropertyValue?) -> Entry? { entries(of: value).first.flatMap(object) }

    /// The list with `member` of entry `index` set to `new`, or removed for nil. The other members of the entry, and
    /// every other entry, are kept.
    static func setting(_ member: String, to new: PropertyValue?, at index: Int, in value: PropertyValue?) -> PropertyValue? {
        var entries = entries(of: value)
        guard entries.indices.contains(index), var fields = object(entries[index]) else { return value }
        fields[member] = new
        entries[index] = .object(fields)
        return .array(entries)
    }

    /// The list with `entry` added at its end.
    static func appending(_ entry: Entry, to value: PropertyValue?) -> PropertyValue {
        .array(entries(of: value) + [.object(entry)])
    }

    /// The list without entry `index`; nil where none is left, so the field is unset rather than holding `[]`.
    static func removing(at index: Int, from value: PropertyValue?) -> PropertyValue? {
        var entries = entries(of: value)
        guard entries.indices.contains(index) else { return value }
        entries.remove(at: index)
        return entries.isEmpty ? nil : .array(entries)
    }

    /// The list with entry `index` moved to `destination` (an index in the list after the move).
    static func moving(from index: Int, to destination: Int, in value: PropertyValue?) -> PropertyValue? {
        var entries = entries(of: value)
        guard entries.indices.contains(index), entries.indices.contains(destination), index != destination else { return value }
        entries.insert(entries.remove(at: index), at: destination)
        return .array(entries)
    }

    /// The list with entry `index` as the main one.
    static func makingMain(_ index: Int, in value: PropertyValue?) -> PropertyValue? { moving(from: index, to: 0, in: value) }
}
