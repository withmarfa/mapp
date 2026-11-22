import SwiftUI

/// A clause's panel content, read from the window as it is now, so a pick shows in it at once: the operators of the field,
/// and the control its value needs.
struct FilterClausePanelHost: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    let index: Int

    var body: some View {
        let content = browser.tableContent(in: library)
        let state = (browser.tableOptions[browser.item] ?? ItemTableOptions()).filter
        if state.clauses.indices.contains(index), let target = content.filterOffer.targets[state.clauses[index].field] {
            let clause = state.clauses[index]
            FilterClausePanel(
                field: target.label, kind: target.kind, op: clause.op,
                setOperator: { browser.setFilterOperator(at: index, to: $0, kind: target.kind) }
            ) {
                valueControl(clause, target: target, content: content)
            }
        }
    }

    @ViewBuilder
    private func valueControl(_ clause: FilterClause, target: FilterTarget, content: ItemTableContent) -> some View {
        let shape = target.kind == .text && clause.op.valueShape == .set ? .single : clause.op.valueShape
        switch shape {
        case .none:
            EmptyView()
        case .set:
            let choices = FilterChoices(target: target, clause: clause, content: content, library: library)
            FilterSetBody(
                chosen: choices.chosen, options: choices.options, searchPrompt: choices.searchPrompt,
                add: { value in browser.changeFilter(at: index) { $0 = $0.adding(value) } },
                remove: { value in browser.changeFilter(at: index) { $0 = $0.removing(value) } })
        case .day, .range:
            FilterDayBody(
                op: clause.op, values: clause.values, calendar: .current, now: library.now(),
                choose: { bound, day in browser.changeFilter(at: index) { $0.values = Self.values(setting: day, at: bound, in: $0) } })
        case .count:
            FilterCountBody(text: clause.values.first ?? "", set: { text in
                browser.changeFilter(at: index) { $0.values = text.isEmpty ? [] : [text] }
            })
        case .single:
            FilterTextBody(
                prompt: target.kind == .number ? "Number" : "Text", text: clause.values.first ?? "",
                set: { text in browser.changeFilter(at: index) { $0.values = text.isEmpty ? [] : [text] } })
        }
    }

    /// The days after choosing one: a single day, or one bound of a range, the two put in order.
    static func values(setting day: String, at bound: Int, in clause: FilterClause) -> [String] {
        guard clause.op == .between else { return [day] }
        var days = clause.values + Array(repeating: "", count: max(0, 2 - clause.values.count))
        days[bound] = day
        if !days[0].isEmpty, !days[1].isEmpty, days[0] > days[1] { days.swapAt(0, 1) }
        return Array(days.prefix(2))
    }
}

/// What a clause's panel lists to choose from: the values chosen, as chips, and those still to pick, from the field's own
/// words and the values the place's items hold, so a value an earlier choice has taken every item out of is still there to
/// take off.
@MainActor
struct FilterChoices {
    var chosen: [ValueChip] = []
    var options: [FilterValueOption] = []
    var searchPrompt: LocalizedStringKey?

    init(target: FilterTarget, clause: FilterClause, content: ItemTableContent, library: any ItemLibrary) {
        let rows = content.allRows
        let held = Set(clause.values)
        let catalogue = library.catalogue
        var listed: [(id: String, title: String, mark: ValueListRow.Mark)] = []
        func row(_ id: String, _ title: String, _ mark: ValueListRow.Mark = .none) { listed.append((id, title, mark)) }
        var marks: [String: ValueListRow.Mark] = [:]
        var titles: [String: String] = [:]

        switch target.kind {
        case .status:
            let words = Self.statusWords(of: target, catalogue: catalogue)
            let groupTitle = { (group: StatusGroup) in StatusBucket.group(group).title }
            for group in StatusGroup.allCases {
                marks[FilterClause.groupValue(group)] = .status(group)
                titles[FilterClause.groupValue(group)] = groupTitle(group)
            }
            for (word, group) in words {
                marks[word] = .status(group)
                titles[word] = ItemTypeInfo.Field.label(ofOption: word)
            }
            let declared = Set(words.map(\.word))
            let undeclared = Set(rows.compactMap { FilterMatching.word(of: $0, target) }).subtracting(declared).sorted()
            for word in undeclared {
                marks[word] = .status(nil)
                titles[word] = ItemTypeInfo.Field.label(ofOption: word)
            }
            var all: [FilterValueOption] = []
            let offerGroupsFirst = content.filterOffer.hasSeveralTypes
            if offerGroupsFirst {
                for group in StatusGroup.allCases {
                    all.append(FilterValueOption(id: FilterClause.groupValue(group), title: groupTitle(group), mark: .status(group), isHeading: true))
                }
            }
            for group in StatusGroup.allCases {
                let inGroup = words.filter { $0.group == group }
                guard !inGroup.isEmpty else { continue }
                if !offerGroupsFirst {
                    all.append(FilterValueOption(id: FilterClause.groupValue(group), title: groupTitle(group), mark: .status(group), isHeading: true))
                } else {
                    all.append(FilterValueOption(id: "heading." + group.rawValue, title: groupTitle(group), isHeading: true, isSelectable: false))
                }
                all += inGroup.map { FilterValueOption(id: $0.word, title: titles[$0.word] ?? $0.word, mark: .status(group), isIndented: true) }
            }
            if !undeclared.isEmpty {
                all.append(FilterValueOption(id: "heading.other", title: StatusBucket.other.title, isHeading: true, isSelectable: false))
                all += undeclared.map { FilterValueOption(id: $0, title: titles[$0] ?? $0, mark: .status(nil), isIndented: true) }
            }
            if rows.contains(where: { FilterMatching.word(of: $0, target) == nil }) {
                all.append(FilterValueOption(id: "", title: String(localized: "No \(target.label)")))
            }
            marks[""] = ValueListRow.Mark.none
            titles[""] = String(localized: "No \(target.label)")
            options = Self.prune(all.filter { !held.contains($0.id) })
            chosen = clause.values.map { ValueChip(id: $0, title: titles[$0] ?? $0, mark: marks[$0] ?? .none) }
            searchPrompt = options.count > 10 ? "Search" : nil
            return
        case .choice:
            guard let field = target.field else { break }
            let isPriority = catalogue.isPriority(field, of: field.declaredBy)
            let values = field.options.filter { !$0.isEmpty } + Set(rows.compactMap { FilterMatching.word(of: $0, target) })
                .subtracting(field.options).sorted()
            for value in values {
                row(value, ItemTypeInfo.Field.label(ofOption: value), .dot(OptionTone.tone(of: value, in: field, isPriority: isPriority)))
            }
            if rows.contains(where: { FilterMatching.word(of: $0, target) == nil }) { row("", String(localized: "No \(target.label)")) }
        case .boolean:
            row("true", String(localized: "Yes"))
            row("false", String(localized: "No"))
            if rows.contains(where: { FilterMatching.word(of: $0, target) == nil }) { row("", String(localized: "No \(target.label)")) }
        case .type:
            let types = Set(rows.map(\.item.type)).union(content.filterOffer.typeIDs)
            for type in types.sorted(by: { (catalogue.itemTypes[$0]?.label ?? $0.rawValue).localizedStandardCompare(catalogue.itemTypes[$1]?.label ?? $1.rawValue) == .orderedAscending }) {
                row(type.rawValue, catalogue.itemTypes[type]?.label ?? type.rawValue, .type(icon: catalogue.icon(for: type)))
            }
        case .parent:
            var seen = Set<String>()
            for related in rows.compactMap(\.parent).sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            where seen.insert(related.id.rawValue).inserted {
                row(related.id.rawValue, related.title)
            }
            if rows.contains(where: { $0.parent == nil }) { row("", String(localized: "No \(target.label)")) }
            searchPrompt = "Search"
        case .collection:
            var seen = Set<String>()
            for related in rows.flatMap(\.collections).sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            where seen.insert(related.id.rawValue).inserted {
                row(related.id.rawValue, related.title)
            }
            searchPrompt = "Search"
        case .source:
            for source in Set(rows.compactMap(\.item.source)).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) { row(source, source) }
            searchPrompt = "Search"
        case .tags:
            var counts: [String: Int] = [:]
            for tag in rows.flatMap(\.item.tags) { counts[tag, default: 0] += 1 }
            for tag in counts.keys.sorted(by: { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0.localizedStandardCompare($1) == .orderedAscending }) {
                row(tag, tag, .tag)
            }
            searchPrompt = "Search Tags"
        case .people:
            var counts: [String: Int] = [:]
            for row in rows { for name in FilterMatching.members(of: row, target) { counts[name, default: 0] += 1 } }
            for name in counts.keys.sorted(by: { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0.localizedStandardCompare($1) == .orderedAscending }) {
                row(name, name, .person(initials: PersonHeader.initials(of: name.split(separator: " ").map(String.init))))
            }
            searchPrompt = "Search People"
        case .date, .number, .text, .moment:
            break
        }
        // A value the clause holds that the place no longer offers is still shown, to be taken off.
        for value in clause.values where !listed.contains(where: { $0.id == value }) {
            listed.append((value, value.isEmpty ? String(localized: "No \(target.label)") : value, .none))
        }
        chosen = clause.values.map { value in
            let found = listed.first { $0.id == value }
            return ValueChip(id: value, title: found?.title ?? value, mark: found?.mark ?? .none)
        }
        options = listed.filter { !held.contains($0.id) }.map { FilterValueOption(id: $0.id, title: $0.title, mark: $0.mark) }
        if searchPrompt == nil, options.count > 10 { searchPrompt = "Search" }
    }

    /// Takes out a heading that has no word left under it.
    private static func prune(_ options: [FilterValueOption]) -> [FilterValueOption] {
        var result: [FilterValueOption] = []
        for (index, option) in options.enumerated() {
            if option.isHeading, !option.isSelectable {
                let next = options.indices.contains(index + 1) ? options[index + 1] : nil
                guard let next, next.isIndented else { continue }
            }
            result.append(option)
        }
        return result
    }

    /// The words every type that declares the status field gives it, each with the group the first of them puts it in, in
    /// the order the types give them.
    static func statusWords(of target: FilterTarget, catalogue: Catalogue) -> [(word: String, group: StatusGroup)] {
        guard let key = target.key else { return [] }
        var words: [(word: String, group: StatusGroup)] = []
        for type in catalogue.itemTypes.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard case .status(let declared)? = catalogue.itemTypes[type]?.fields.first(where: { $0.key == key })?.kind else { continue }
            for word in declared where !words.contains(where: { $0.word == word.value }) { words.append((word.value, word.group)) }
        }
        return words
    }
}
