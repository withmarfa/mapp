import AppKit
import SwiftUI

// The panels a filter chip and the + open, and the bodies they hold. They take rows and actions and know nothing of
// `Browser`. The View panel's Filter opens them in a popover; on the Items page `FilterPanelPresenter` puts one on the
// screen, from the row in `FilterChips.swift`.

/// A value a filter can take, as the panel lists it.
struct FilterValueOption: Identifiable, Hashable {
    let id: String
    var title: String
    var mark: ValueListRow.Mark = .none
    /// Words at the row's trailing edge, such as the day a quick date is.
    var detail: String?
    /// A heading over the rows below it, which picks them all where it is selectable (a status group).
    var isHeading = false
    var isSelectable = true
    /// Whether the row sits under a heading.
    var isIndented = false
}

/// A field a filter can be added on, as the Filter By panel lists it.
struct FilterFieldOption: Identifiable, Hashable {
    let id: String
    var title: String
    var symbol: String
}

/// A run of fields under a heading in Filter By: the place's types' fields, then what every item has.
struct FilterFieldSection: Identifiable, Hashable {
    var title: String
    var fields: [FilterFieldOption]
    var id: String { title }
}

/// The operators a field takes, as a pop-up: the fixed ones first, then presence, then dates relative to today under their own
/// heading.
struct FilterOperatorMenu: View {
    let kind: FilterKind
    let op: FilterOp
    /// Whether the dates relative to today are offered.
    var offersRelative = true
    let choose: (FilterOp) -> Void

    static func sections(for kind: FilterKind, relative: Bool = true) -> [(title: String?, ops: [FilterOp])] {
        var result: [(title: String?, ops: [FilterOp])] = []
        for entry in FilterOp.offered(for: kind) where relative || !entry.op.isRelative {
            if entry.startsSection || result.isEmpty {
                result.append((entry.op.isRelative ? String(localized: "Relative to Today") : nil, []))
            }
            result[result.count - 1].ops.append(entry.op)
        }
        return result
    }

    var body: some View {
        let sections = Self.sections(for: kind, relative: offersRelative)
        Menu {
            ForEach(sections.indices, id: \.self) { index in
                if let title = sections[index].title {
                    Section(title) { picker(sections[index].ops) }
                } else {
                    picker(sections[index].ops)
                }
            }
        } label: {
            Text(verbatim: op.word(for: kind))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Operator")
        .accessibilityIdentifier("FilterRelation")
    }

    private func picker(_ ops: [FilterOp]) -> some View {
        Picker("Operator", selection: Binding(get: { op }, set: { choose($0) })) {
            ForEach(ops, id: \.self) { Text(verbatim: $0.menuTitle(for: kind)).tag($0) }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}

/// A chip's panel: the field's name, a pop-up of the operators it takes, then the control its value needs.
struct FilterClausePanel<Content: View>: View {
    let field: String
    let kind: FilterKind
    let op: FilterOp
    var offersRelative = true
    let setOperator: (FilterOp) -> Void
    @ViewBuilder let content: Content
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(spacing: 6 * scale) {
                Text(verbatim: field).fontWeight(.semibold)
                FilterOperatorMenu(kind: kind, op: op, offersRelative: offersRelative, choose: setOperator)
                Spacer(minLength: 0)
            }
            .font(.system(size: ValueEditMetrics.textSize * scale))
            .padding(.horizontal, 8 * scale)
            .padding(.top, 4 * scale)
            content
        }
        .padding(.bottom, ValueEditMetrics.padding * scale)
        .accessibilityIdentifier("FilterValuePanel")
    }
}

/// A set of values: the chosen ones as chips in a field, then those still to pick, flush left with their marks. Picking adds a
/// value and the panel stays open, since a filter holds several. A long list has a search field.
struct FilterSetBody: View {
    let chosen: [ValueChip]
    let options: [FilterValueOption]
    var searchPrompt: LocalizedStringKey?
    let add: (String) -> Void
    let remove: (String) -> Void
    @State private var query = ""
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let shown = query.isEmpty ? options : options.filter { $0.isSelectable && !$0.isHeading && $0.title.localizedStandardContains(query) }
        VStack(alignment: .leading, spacing: 6 * scale) {
            ChipFieldLayout(spacing: 4 * scale, lineHeight: 20 * scale) {
                ForEach(chosen) { chip in
                    ValueChipView(chip: chip, scale: scale) { remove(chip.id) }
                }
                if chosen.isEmpty {
                    Text("Choose a value").font(.system(size: 12 * scale)).foregroundStyle(.tertiary)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .padding(6 * scale)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 7 * scale, style: .continuous))
            .padding(.horizontal, ValueEditMetrics.padding * scale)
            if let searchPrompt {
                TextField(searchPrompt, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: ValueEditMetrics.textSize * scale))
                    .padding(.horizontal, 8 * scale)
                    .frame(height: 28 * scale)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 7 * scale, style: .continuous))
                    .appFocusRing(.rect(cornerRadius: 7 * scale, style: .continuous))
                    .padding(.horizontal, ValueEditMetrics.padding * scale)
                    .accessibilityIdentifier("FilterValueSearch")
            }
            Divider().padding(.horizontal, 8 * scale)
            if shown.isEmpty {
                Group {
                    if query.isEmpty { Text("No more values") } else { Text("No Matching Values") }
                }
                .foregroundStyle(.secondary)
                .font(.system(size: ValueEditMetrics.textSize * scale))
                .padding(.horizontal, 8 * scale)
                .frame(height: ValueEditMetrics.rowHeight * scale)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(shown) { option in
                            FilterOptionRow(option: option, scale: scale) { add(option.id) }
                        }
                    }
                    .padding(.horizontal, ValueEditMetrics.padding * scale)
                }
                .frame(height: min(CGFloat(shown.count), CGFloat(ValueEditMetrics.visibleRows)) * ValueEditMetrics.rowHeight * scale)
            }
        }
    }
}

/// A day: the quick days, then a month to choose from. Between takes two, From and To, the calendar filling the one
/// that is lit and then the other.
struct FilterDayBody: View {
    let op: FilterOp
    let values: [String]
    let calendar: Calendar
    let now: Date
    let choose: (Int, String) -> Void
    @State private var bound = 0
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let isRange = op == .between
        let index = isRange ? bound : 0
        let selected = values.indices.contains(index) ? FilterDays.start(of: values[index], calendar: calendar) : nil
        VStack(alignment: .leading, spacing: 0) {
            if isRange {
                HStack(spacing: 6 * scale) {
                    boundButton("From", at: 0, scale: scale)
                    boundButton("To", at: 1, scale: scale)
                }
                .padding(.horizontal, ValueEditMetrics.padding * scale)
                .padding(.bottom, 6 * scale)
            }
            VStack(spacing: 0) {
                ForEach(QuickDates.entries(now: now, calendar: calendar, includingTwoWeeks: true)) { entry in
                    FilterOptionRow(
                        option: FilterValueOption(
                            id: entry.id, title: entry.title, mark: .symbol(entry.symbol),
                            detail: QuickDates.detail(of: entry, now: now, calendar: calendar, locale: calendar.locale ?? .current)),
                        scale: scale
                    ) { pick(entry.date) }
                }
            }
            .padding(.horizontal, ValueEditMetrics.padding * scale)
            Divider().padding(.vertical, 5 * scale).padding(.horizontal, 8 * scale)
            ValueCalendar(selected: selected, today: now, calendar: calendar, scale: scale) { pick($0) }
                .accessibilityIdentifier("FilterDate")
        }
    }

    private func pick(_ date: Date) {
        let index = op == .between ? bound : 0
        choose(index, FilterDays.text(of: date, calendar: calendar))
        if op == .between { bound = 1 - bound }
    }

    private func boundButton(_ title: LocalizedStringKey, at index: Int, scale: CGFloat) -> some View {
        let day = values.indices.contains(index) ? values[index] : ""
        return Button { bound = index } label: {
            HStack(spacing: 4 * scale) {
                Text(title).foregroundStyle(.secondary)
                Text(verbatim: day.isEmpty ? "…" : FilterWording.day(day, calendar: calendar))
            }
            .font(.system(size: 12 * scale))
            .padding(.horizontal, 8 * scale)
            .frame(maxWidth: .infinity, minHeight: 24 * scale)
            .background(.quaternary.opacity(bound == index ? 0.9 : 0.4), in: .rect(cornerRadius: 6 * scale, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A count of days, for the last or the next.
struct FilterCountBody: View {
    let text: String
    let set: (String) -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: 6 * scale) {
            TextField("Days", text: Binding(get: { text }, set: { set($0.filter(\.isNumber)) }), prompt: Text(verbatim: "7"))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .multilineTextAlignment(.trailing)
                .frame(width: 56 * scale, height: 26 * scale)
                .padding(.horizontal, 6 * scale)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 7 * scale, style: .continuous))
                .appFocusRing(.rect(cornerRadius: 7 * scale, style: .continuous), isFocused: isFocused)
                .accessibilityIdentifier("FilterCount")
            Text("days").foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.system(size: ValueEditMetrics.textSize * scale))
        .padding(.horizontal, ValueEditMetrics.padding * scale + 3 * scale)
        .onAppear { isFocused = true }
    }
}

/// A number or a text, typed.
struct FilterTextBody: View {
    let prompt: LocalizedStringKey
    let text: String
    let set: @MainActor (String) -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        TextField(prompt, text: Binding(get: { text }, set: set))
            .textFieldStyle(.plain)
            .focused($isFocused)
            .font(.system(size: ValueEditMetrics.textSize * scale))
            .padding(.horizontal, 8 * scale)
            .frame(height: 28 * scale)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 7 * scale, style: .continuous))
            .appFocusRing(.rect(cornerRadius: 7 * scale, style: .continuous), isFocused: isFocused)
            .padding(.horizontal, ValueEditMetrics.padding * scale)
            .onAppear { isFocused = true }
            .accessibilityIdentifier("FilterText")
    }
}

/// The command palette's chip panel: the field's name, an is / is not pop-up, the chosen values as chips in a field, then the
/// values still to pick, flush left with their marks. Picking adds a value and the panel stays open, since a filter holds several.
struct FilterValuePanel: View {
    let field: String
    let isNegated: Bool
    let chosen: [ValueChip]
    let options: [FilterValueOption]
    let setNegated: @MainActor (Bool) -> Void
    let add: (String) -> Void
    let remove: (String) -> Void
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(spacing: 6 * scale) {
                Text(verbatim: field).fontWeight(.semibold)
                Picker("Relation", selection: Binding(get: { isNegated }, set: setNegated)) {
                    Text("is").tag(false)
                    Text("is not").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier("FilterRelation")
                Spacer(minLength: 0)
            }
            .font(.system(size: ValueEditMetrics.textSize * scale))
            .padding(.horizontal, 8 * scale)
            .padding(.top, 4 * scale)
            ChipFieldLayout(spacing: 4 * scale, lineHeight: 20 * scale) {
                ForEach(chosen) { chip in
                    ValueChipView(chip: chip, scale: scale) { remove(chip.id) }
                }
                if chosen.isEmpty {
                    Text("Choose a value").font(.system(size: 12 * scale)).foregroundStyle(.tertiary)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .padding(6 * scale)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 7 * scale, style: .continuous))
            .padding(.horizontal, ValueEditMetrics.padding * scale)
            Divider().padding(.horizontal, 8 * scale)
            if options.isEmpty {
                Text("No more values").foregroundStyle(.secondary)
                    .font(.system(size: ValueEditMetrics.textSize * scale))
                    .padding(.horizontal, 8 * scale)
                    .frame(height: ValueEditMetrics.rowHeight * scale)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(options) { option in
                            FilterOptionRow(option: option, scale: scale) { add(option.id) }
                        }
                    }
                    .padding(.horizontal, ValueEditMetrics.padding * scale)
                }
                .frame(height: min(CGFloat(options.count), CGFloat(ValueEditMetrics.visibleRows)) * ValueEditMetrics.rowHeight * scale)
            }
        }
        .padding(.bottom, ValueEditMetrics.padding * scale)
        .accessibilityIdentifier("FilterValuePanel")
    }
}


/// The Filter By panel (N7): a search field, then the fields a filter can be added on, each with its symbol, in the sections
/// the place gives. Choosing one adds its chip; a field already filtered takes a second condition. The foot says how many
/// conditions a view keeps once the row is near it.
struct FilterFieldPanel: View {
    let sections: [FilterFieldSection]
    var footer: String?
    let pick: (String) -> Void

    init(sections: [FilterFieldSection], footer: String? = nil, pick: @escaping (String) -> Void) {
        self.sections = sections
        self.footer = footer
        self.pick = pick
    }

    /// One run of fields with no heading, as the palette's filters list them.
    init(fields: [FilterFieldOption], pick: @escaping (String) -> Void) {
        self.init(sections: [FilterFieldSection(title: "", fields: fields)], pick: pick)
    }

    @State private var query = ""
    @FocusState private var isFocused: Bool
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let shown = sections.map { section in
            FilterFieldSection(
                title: section.title, fields: query.isEmpty ? section.fields : section.fields.filter { $0.title.localizedStandardContains(query) })
        }.filter { !$0.fields.isEmpty }
        let first = shown.first?.fields.first
        let rows = shown.reduce(0) { $0 + $1.fields.count + 1 }
        VStack(alignment: .leading, spacing: 4 * scale) {
            TextField("Filter By", text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(.system(size: ValueEditMetrics.textSize * scale))
                .padding(.horizontal, 8 * scale)
                .frame(height: 28 * scale)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 7 * scale, style: .continuous))
                .appFocusRing(.rect(cornerRadius: 7 * scale, style: .continuous), isFocused: isFocused)
                .padding(.horizontal, ValueEditMetrics.padding * scale)
                .padding(.top, ValueEditMetrics.padding * scale)
                .onSubmit { if let first { pick(first.id) } }
                .accessibilityIdentifier("FilterBySearch")
            if shown.isEmpty {
                Text("No Matching Fields").foregroundStyle(.secondary)
                    .font(.system(size: ValueEditMetrics.textSize * scale))
                    .padding(.horizontal, 8 * scale)
                    .frame(height: ValueEditMetrics.rowHeight * scale)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { section in
                            if !section.title.isEmpty {
                                Text(verbatim: section.title)
                                    .font(.system(size: 11 * scale, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8 * scale)
                                    .frame(height: ValueEditMetrics.headerHeight * scale, alignment: .bottom)
                            }
                            ForEach(section.fields) { field in
                                FilterOptionRow(
                                    option: FilterValueOption(id: field.id, title: field.title, mark: .symbol(field.symbol)), scale: scale
                                ) { pick(field.id) }
                            }
                        }
                    }
                    .padding(.horizontal, ValueEditMetrics.padding * scale)
                }
                .frame(height: min(CGFloat(rows), CGFloat(ValueEditMetrics.visibleRows + 2)) * ValueEditMetrics.rowHeight * scale)
            }
            if let footer {
                Divider().padding(.horizontal, 8 * scale)
                Text(verbatim: footer)
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 2 * scale)
                    .accessibilityIdentifier("FilterByFooter")
            }
        }
        .padding(.bottom, ValueEditMetrics.padding * scale)
        .onAppear { isFocused = true }
        .accessibilityIdentifier("FilterFieldPanel")
    }
}

/// One line of any panel, as a value panel draws its rows: the mark, the title, and the gray under the pointer. A heading
/// that picks nothing is only a label.
private struct FilterOptionRow: View {
    let option: FilterValueOption
    let scale: CGFloat
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lit = isHovered && option.isSelectable
        HStack(spacing: 7 * scale) {
            ValueMarkView(mark: option.mark, scale: scale)
            Text(verbatim: option.title)
                .fontWeight(option.isHeading ? .semibold : .regular)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8 * scale)
            if let detail = option.detail {
                Text(verbatim: detail).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: ValueEditMetrics.textSize * scale))
        .foregroundStyle(option.isSelectable ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .padding(.leading, (option.isIndented ? 22 : 8) * scale)
        .padding(.trailing, 8 * scale)
        .frame(height: ValueEditMetrics.rowHeight * scale)
        .background {
            if lit {
                RoundedRectangle(cornerRadius: ValueEditMetrics.rowRadius * scale, style: .continuous).fill(SelectionLooks.chosen(for: scheme))
            }
        }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture { if option.isSelectable { action() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(option.isSelectable ? .isButton : [])
        .accessibilityAction(.default) { if option.isSelectable { action() } }
        .accessibilityIdentifier("FilterOption.\(option.id)")
    }
}
