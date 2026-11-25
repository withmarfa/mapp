import Foundation

/// What Group by offers for a place, worked out once and drawn alike by View Options, the View menu and Edit View
/// ([docs/lists.md](../../../docs/lists.md#grouping)). The fields come from the types the place lists
/// (`Browser.listedTypes`), and the types of its items, never only from the items on screen, so a field no item fills
/// can still be chosen; such a field waits under More Fields.
///
/// In order: None (not on a board, which always has lanes); Status, as Words and Groups where both apply, else one item;
/// the choice and yes-or-no fields, then each date with its spans and Set or Not Set; then Type where the place shows
/// several types, Parent, Created, Edited and Happened; then More Fields, every other optional field with Set or Not Set.
nonisolated struct GroupOffer: Hashable, Sendable {
    /// One way to group, as a menu item.
    struct Choice: Hashable, Sendable, Identifiable {
        var label: String
        var grouping: ItemTableOptions.Grouping
        /// Whether a divider comes before it: Set or Not Set follows a date's spans.
        var startsSection = false
        /// Whether a saved view can hold it; one it cannot is shown, and not offered, in a saved view.
        var isKept = true
        var id: ItemTableOptions.Grouping { grouping }
    }

    /// A field or part of an item: one choice is a plain item, several a submenu.
    struct Entry: Hashable, Sendable, Identifiable {
        var id: String
        var label: String
        var choices: [Choice]

        /// The choices in runs, a new one at each choice that starts a section: a picker draws a divider between runs,
        /// never inside the element a choice is tagged in, where the divider would take the choice's tag.
        var runs: [[Choice]] {
            choices.reduce(into: []) { runs, choice in
                if choice.startsSection || runs.isEmpty { runs.append([choice]) } else { runs[runs.count - 1].append(choice) }
            }
        }
    }

    var offersNone: Bool
    /// Runs of entries with a divider between them.
    var sections: [[Entry]]
    var moreFields: [Entry]

    /// Every entry, More Fields last.
    var entries: [Entry] { sections.flatMap { $0 } + moreFields }

    /// The entry and choice that stand for a grouping, where the offer has it.
    func entry(for grouping: ItemTableOptions.Grouping) -> (entry: Entry, choice: Choice)? {
        for entry in entries {
            if let choice = entry.choices.first(where: { $0.grouping == grouping }) { return (entry, choice) }
        }
        return nil
    }

    /// What a layout that always has groups shows where the place's own choice is none, or one it cannot show: the
    /// status, by its words where they are offered, else the first field offered. The place's choice stays as it is.
    var fallback: ItemTableOptions.Grouping? {
        let first = sections.first { !$0.isEmpty }?.first ?? moreFields.first
        return (sections.first?.first { $0.id == Self.statusID } ?? first)?.choices.first { $0.isKept }?.grouping
            ?? first?.choices.first?.grouping
    }

    static let statusID = "\u{1}status"

    /// The offer for a place's `columns`, which hold every field of the `types` it lists; `rows` tell which fields
    /// some item fills. `layout` leaves out what it cannot show, and `isView` marks what a saved view cannot hold.
    static func make(
        columns: [ItemTableColumn], types: Set<TypeID>, rows: [ItemTableRow], catalogue: Catalogue, layout: ItemViewMode, isView: Bool
    ) -> GroupOffer {
        let byID = Dictionary(columns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sortedTypes = types.sorted { $0.rawValue < $1.rawValue }
        func kept(_ mode: GroupMode) -> Bool { !isView || mode.isKeptByView }
        func choice(_ label: String, _ id: String, _ mode: GroupMode, startsSection: Bool = false) -> Choice {
            Choice(label: label, grouping: .column(id, by: mode), startsSection: startsSection, isKept: kept(mode))
        }
        func spans(_ id: String, presence: Bool) -> [Choice] {
            LibraryViewGroup.Bucket.allCases.map { choice($0.title, id, .bucket($0)) }
                + (presence ? [choice(GroupMode.presence.title, id, .presence, startsSection: true)] : [])
        }
        func isFilled(_ key: String) -> Bool { rows.contains { InspectorFields.hasValue($0.item.value(of: key)) } }

        // The status: by words where every type that has the field declares the same ones, else by Marfa's groups.
        var statusEntry: Entry?
        let statusFields = sortedTypes.compactMap { catalogue.itemTypes[$0]?.statusField }
        if let first = statusFields.first, let column = byID[Browser.fieldColumnPrefix + first.key] {
            let oneKey = statusFields.allSatisfy { $0.key == first.key }
            let sameWords = oneKey && statusFields.allSatisfy { $0.options == first.options }
            let groups = choice(GroupMode.statusGroups.title, column.id, .statusGroups)
            statusEntry = Entry(
                id: statusID, label: column.label,
                choices: sameWords ? [choice(GroupMode.value.title, column.id, .value), groups] : [groups])
        }

        // The type's own fields, in the order the types declare them, each once.
        var picked: [Entry] = []
        var dates: [Entry] = []
        var more: [Entry] = []
        // The Status item stands for every type's status field, whatever its key, so none is offered again.
        var seen: Set<String> = statusEntry == nil ? [] : Set(statusFields.map(\.key))
        for type in sortedTypes {
            guard let info = catalogue.itemTypes[type] else { continue }
            let page: Set<String> = [info.titleKey, info.bodyKey, "title", "body"].compactMap { $0 }.reduce(into: []) { $0.insert($1) }
            for field in info.fields where !page.contains(field.key) && seen.insert(field.key).inserted {
                guard let column = byID[Browser.fieldColumnPrefix + field.key] else { continue }
                let optional = !field.required
                let filled = isFilled(field.key)
                var choices: [Choice]
                switch column.style {
                case .choice, .priority, .status:
                    choices = [choice(filled ? column.label : String(localized: "Each Option"), column.id, .value)]
                case .boolean:
                    choices = [choice(filled ? column.label : String(localized: "Yes or No"), column.id, .value)]
                case .date:
                    choices = spans(column.id, presence: optional)
                default:
                    choices = []
                }
                if filled, !choices.isEmpty {
                    if column.style == .date {
                        dates.append(Entry(id: column.id, label: column.label, choices: choices))
                    } else {
                        picked.append(Entry(id: column.id, label: column.label, choices: choices))
                    }
                    continue
                }
                // A field no item fills waits here, with Set or Not Set where it may be empty (a date's spans hold it already).
                if optional, column.groups(by: .presence), column.style != .date {
                    choices.append(choice(GroupMode.presence.title, column.id, .presence, startsSection: !choices.isEmpty))
                }
                if !choices.isEmpty { more.append(Entry(id: column.id, label: column.label, choices: choices)) }
            }
        }

        // What every item has.
        var own: [Entry] = []
        if let type = byID[ItemTableColumn.type.id] {
            own.append(Entry(id: type.id, label: type.label, choices: [choice(type.label, type.id, .value)]))
        }
        if layout != .board, byID[ItemTableColumn.parent.id] != nil {
            let label = String(localized: "Parent")
            own.append(Entry(id: ItemTableColumn.parent.id, label: label, choices: [choice(label, ItemTableColumn.parent.id, .value)]))
        }
        // Every item has these dates, so they offer their spans alone.
        for column in [ItemTableColumn.created, .edited, .occurred] {
            own.append(Entry(id: column.id, label: column.label, choices: spans(column.id, presence: false)))
        }

        let first = [statusEntry].compactMap { $0 } + picked + dates
        return GroupOffer(offersNone: layout != .board, sections: [first, own].filter { !$0.isEmpty }, moreFields: more)
    }
}
