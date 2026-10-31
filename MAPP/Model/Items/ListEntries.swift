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
        switch (minimum, maximum) {
        case (let low?, let high?): String(localized: "Enter a number from \(PropertyNumber.editing(low)) to \(PropertyNumber.editing(high)).")
        case (let low?, nil): String(localized: "Enter a number of \(PropertyNumber.editing(low)) or more.")
        case (nil, let high?): String(localized: "Enter a number of \(PropertyNumber.editing(high)) or less.")
        case (nil, nil): integer ? String(localized: "Enter a whole number.") : nil
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

        /// A member that tells entries apart rather than being their content, such as a label or a response.
        var isQualifier: Bool {
            if case .choice = kind { return true }
            return key == ListShape.labelKey
        }

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

    /// The member Marfa's own lists use for a name an entry goes by ("work", "home").
    static let labelKey = "label"

    /// The members, in the order the type declares them.
    let members: [Member]

    func member(_ key: String) -> Member? { members.first { $0.key == key } }

    /// Whether `entry` is an entry of this list: an object with at least one member, only members the list declares,
    /// and a value each member takes.
    func accepts(_ entry: PropertyValue) -> Bool {
        guard case .object(let fields) = entry, !fields.isEmpty else { return false }
        return fields.allSatisfy { key, value in member(key)?.accepts(value) == true }
    }

    /// Why `entry` cannot be written, or nil where it can: a required member is missing, a member is out of range, or
    /// the entry has no member at all.
    func refusal(of entry: [String: PropertyValue]) -> String? {
        if entry.isEmpty { return String(localized: "An entry needs at least one value.") }
        for member in members {
            guard let value = entry[member.key] else {
                if member.required { return String(localized: "\(member.label) is required.") }
                continue
            }
            if !member.accepts(value) {
                if case .number(let rule) = member.kind, let requirement = rule.requirement { return requirement }
                return String(localized: "\(member.label) isn’t a valid value.")
            }
        }
        return nil
    }

    /// The words that stand for an entry in a row or a table cell: its descriptive members joined, or its identifying
    /// ones (an address that names no one) where it has none, then its qualifiers in brackets.
    func summary(of entry: [String: PropertyValue]) -> String {
        func text(_ member: Member) -> String? {
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
        let content = members.filter { !$0.isQualifier }
        let isIdentifier: (Member) -> Bool = {
            if case .text(let format) = $0.kind { format != nil } else { false }
        }
        let descriptive = content.filter { !isIdentifier($0) }.compactMap(text)
        let main = descriptive.isEmpty ? content.compactMap(text) : descriptive
        let qualifiers = members.filter(\.isQualifier).compactMap(text)
        let head = main.joined(separator: ", ")
        guard !qualifiers.isEmpty else { return head }
        let tail = "(" + qualifiers.joined(separator: ", ") + ")"
        return head.isEmpty ? tail : head + " " + tail
    }

    /// What a table cell holds: the main entry's summary, and how many more the list has ("ann@x.com +2").
    func display(of value: PropertyValue) -> String {
        let entries = ListEntries.entries(of: value)
        guard let main = entries.first.flatMap(ListEntries.object) else { return ItemValueText.string(value) }
        let head = summary(of: main)
        return entries.count > 1 ? head + " +\(entries.count - 1)" : head
    }

    /// How a page row shows an entry: its first identifying member as a link where that is an address, else the whole
    /// summary as text. Nil where the entry has nothing to show.
    func rowValue(of entry: [String: PropertyValue]) -> PropertyRow.Value? {
        let summary = summary(of: entry)
        guard !summary.isEmpty else { return nil }
        let first = members.first { !$0.isQualifier && entry[$0.key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        if let first, case .text(let format?) = first.kind, let text = entry[first.key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return format == .email ? .email(text) : .url(text)
        }
        return .text(summary)
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
