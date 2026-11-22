import AppKit
import MarfaIcons
import SwiftUI

// The row of filters above a list, and the two panels it opens. Nothing here knows `Browser`: the row takes chips and
// actions, the panels take rows and actions, so the command palette's filter row can use them as they are. `FilterRow`
// is the adaptor that maps a window's filters onto them.

/// One filter as the row draws it: "Status is not Completed, Canceled".
struct FilterChipItem: Identifiable, Hashable {
    let id: String
    /// The field's name, drawn grey.
    var field: String
    /// "is" or "is not".
    var relation: String
    /// The values, joined; empty while the chip waits for its first value.
    var values: String
    /// Whether the chip says a value at all: "is set" says none, and a chip that waits for one shows an ellipsis.
    var needsValue = true
    /// A condition the row cannot change, such as a saved view's text search: shown so it is not hidden, and kept.
    var isLocked = false
    /// Why a locked chip is locked.
    var lockedReason: String?
}

/// Holds the views the panels open under, which the row's SwiftUI body cannot reach: one per chip, and the +.
@MainActor
final class FilterChipAnchors {
    static let addKey = "+"
    private var views: [String: Weak] = [:]

    private struct Weak { weak var view: NSView? }

    func view(for key: String) -> NSView? { views[key]?.view }

    fileprivate func set(_ view: NSView, for key: String) { views[key] = Weak(view: view) }
}

/// A view laid behind a chip, for its panel to open under. It takes no clicks.
private struct FilterAnchor: NSViewRepresentable {
    let anchors: FilterChipAnchors
    let key: String

    func makeNSView(context: Context) -> NSView {
        let view = PassiveView()
        anchors.set(view, for: key)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchors.set(view, for: key) }

    private final class PassiveView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The measures of the row, which the palette's filter row shares.
enum FilterChipMetrics {
    static let height: CGFloat = 26
    static let radius: CGFloat = 6
    static let widest: CGFloat = 300
    static let spacing: CGFloat = 6
}

/// The pop-up at the row's leading edge once it holds two filters: All or Any.
struct FilterMatchPicker {
    var isAny: Bool
    let choose: (Bool) -> Void
}

/// The filters of a place as squared chips of one height, ending in a square +. A long row scrolls sideways, so it never
/// pushes the list off. The chips start at `leadingInset`, which a layout sets to its own left edge. Once the row holds two
/// filters a pop-up leads it (`matchPicker`); `trailingNote` ends the row, and `note` says under the chips what a view cannot keep.
struct FilterChipsBar: View {
    let chips: [FilterChipItem]
    var leadingInset: CGFloat = 12
    /// The palette shows no tooltips; a list's row does.
    var showsHelp = true
    var matchPicker: FilterMatchPicker?
    var trailingNote: String?
    var note: String?
    let anchors: FilterChipAnchors
    let open: (String) -> Void
    let remove: (String) -> Void
    let add: () -> Void
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: FilterChipMetrics.spacing) {
                if let matchPicker {
                    matchMenu(matchPicker, scale: scale)
                        .padding(.leading, leadingInset)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: FilterChipMetrics.spacing) {
                        ForEach(chips) { chip in
                            FilterChipView(chip: chip, scale: scale, open: { open(chip.id) }, remove: { remove(chip.id) })
                                .background { FilterAnchor(anchors: anchors, key: chip.id) }
                        }
                        Button(action: add) {
                            Image(systemName: "plus")
                                .font(.system(size: 11 * scale, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: FilterChipMetrics.height * scale, height: FilterChipMetrics.height * scale)
                                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: FilterChipMetrics.radius * scale, style: .continuous))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .background { FilterAnchor(anchors: anchors, key: FilterChipAnchors.addKey) }
                        .help(showsHelp ? String(localized: "Add a filter") : "")
                        .accessibilityLabel("Add Filter")
                        .accessibilityIdentifier("FilterChipAdd")
                    }
                    .padding(.leading, matchPicker == nil ? leadingInset : 0)
                    .padding(.trailing, trailingNote == nil ? leadingInset : 0)
                }
                .scrollIndicators(.never)
                if let trailingNote {
                    Text(verbatim: trailingNote)
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.trailing, leadingInset)
                        .fixedSize()
                        .accessibilityIdentifier("FilterRelativeNote")
                }
            }
            .padding(.vertical, 6)
            if let note {
                Text(verbatim: note)
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, leadingInset)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("FilterRowNote")
            }
        }
        .accessibilityIdentifier("FilterChips")
    }

    private func matchMenu(_ picker: FilterMatchPicker, scale: CGFloat) -> some View {
        Menu {
            Picker("All of these", selection: Binding(get: { picker.isAny }, set: picker.choose)) {
                Text("All").tag(false)
                Text("Any").tag(true)
            }
            .pickerStyle(.inline)
        } label: {
            Text(picker.isAny ? "Any" : "All")
                .font(.system(size: 12 * scale))
                .frame(height: FilterChipMetrics.height * scale)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("All of these")
        .accessibilityIdentifier("FilterMatch")
    }
}

private struct FilterChipView: View {
    let chip: FilterChipItem
    let scale: CGFloat
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4 * scale) {
            Button(action: open) {
                HStack(spacing: 4 * scale) {
                    Text(verbatim: chip.field).foregroundStyle(.secondary)
                    Text(verbatim: chip.relation)
                    if chip.needsValue || !chip.values.isEmpty {
                        Text(verbatim: chip.values.isEmpty ? "…" : chip.values).lineLimit(1).truncationMode(.tail)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(chip.isLocked)
            if chip.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(.tertiary)
                    .help(chip.lockedReason ?? "")
            } else {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 8 * scale, weight: .bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove Filter")
            }
        }
        .font(.system(size: 12 * scale))
        .padding(.horizontal, 8 * scale)
        .frame(height: FilterChipMetrics.height * scale)
        .frame(maxWidth: FilterChipMetrics.widest * scale)
        .background(.quaternary.opacity(chip.isLocked ? 0.35 : 0.6), in: .rect(cornerRadius: FilterChipMetrics.radius * scale, style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FilterChip")
    }
}

// MARK: Panels

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
    let choose: (FilterOp) -> Void

    static func sections(for kind: FilterKind) -> [(title: String?, ops: [FilterOp])] {
        var result: [(title: String?, ops: [FilterOp])] = []
        for entry in FilterOp.offered(for: kind) {
            if entry.startsSection || result.isEmpty {
                result.append((entry.op.isRelative ? String(localized: "Relative to Today") : nil, []))
            }
            result[result.count - 1].ops.append(entry.op)
        }
        return result
    }

    var body: some View {
        let sections = Self.sections(for: kind)
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
    let setOperator: (FilterOp) -> Void
    @ViewBuilder let content: Content
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(spacing: 6 * scale) {
                Text(verbatim: field).fontWeight(.semibold)
                FilterOperatorMenu(kind: kind, op: op, choose: setOperator)
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
    let set: (String) -> Void
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
    let setNegated: (Bool) -> Void
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

/// One line of any panel, as a value panel draws its rows: the mark, the title, and the accent under the pointer. A heading
/// that picks nothing is only a label.
private struct FilterOptionRow: View {
    let option: FilterValueOption
    let scale: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let lit = isHovered && option.isSelectable
        HStack(spacing: 7 * scale) {
            ValueMarkView(mark: option.mark, scale: scale, onAccent: lit)
            Text(verbatim: option.title)
                .fontWeight(option.isHeading ? .semibold : .regular)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8 * scale)
            if let detail = option.detail {
                Text(verbatim: detail).foregroundStyle(lit ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
        }
        .font(.system(size: ValueEditMetrics.textSize * scale))
        .foregroundStyle(lit ? AnyShapeStyle(.white) : AnyShapeStyle(option.isSelectable ? .primary : .secondary))
        .padding(.leading, (option.isIndented ? 22 : 8) * scale)
        .padding(.trailing, 8 * scale)
        .frame(height: ValueEditMetrics.rowHeight * scale)
        .background {
            if lit {
                RoundedRectangle(cornerRadius: ValueEditMetrics.rowRadius * scale, style: .continuous).fill(Color.accentColor)
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

// MARK: Presenter

/// Opens one panel at a time under a chip or the +, in a child window on the system's glass, as a value panel opens. It
/// closes on a click outside, Escape, the app going to the background and the window resizing, and calls `onClose` then.
@MainActor
final class FilterPanelPresenter {
    static let shared = FilterPanelPresenter()

    private var panel: ValueEditPanel?
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private var key: String?
    private var onClose: (() -> Void)?
    private var width: CGFloat = 280
    private var height: CGFloat = 120
    private var layoutPending = false
    /// A click on a chip while its panel is open closes it as an outside click, and then asks to open it again, which
    /// would put it straight back; the chip toggles instead.
    private var closedByClick: (key: String, at: Date)?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    /// Follows the window's appearance, so a panel left open does not keep the one it opened in.
    private var appearanceWatch: NSKeyValueObservation?

    var isOpen: Bool { panel != nil }

    /// Whether the panel open is the one `key` names.
    func isOpen(for key: String) -> Bool { panel != nil && self.key == key }

    /// Opens `content` under `anchor`, or closes it where `key` is the panel already open or was just closed by the click
    /// that asks to open it.
    func present<Content: View>(key: String, anchor: NSView?, width: CGFloat, onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        if let open = self.key, panel != nil {
            dismiss()
            if open == key { return }
        }
        if let closed = closedByClick {
            closedByClick = nil
            if closed.key == key, Date.now.timeIntervalSince(closed.at) < 0.4 { return }
        }
        guard let anchor, let window = anchor.window else { return }
        self.key = key
        self.anchor = anchor
        self.parent = window
        self.onClose = onClose
        self.width = width * InterfaceStyle.scale(for: storedTextSize)
        let measured = content()
            .frame(width: self.width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak self] in
                self?.height = $0
                self?.layoutSoon()
            }
            .interfaceTextStyle()
        let host = NSHostingView(rootView: measured)
        host.sizingOptions = []
        let panel = ValueEditPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = window.effectiveAppearance
        panel.contentView = ValueEditPanelSession.surface(holding: host, style: ValuePanelStyle.stored(), appearance: panel.appearance)
        self.panel = panel
        layout()
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        watch()
    }

    /// Closes the panel open, if any, and tells its owner.
    func dismiss(restoringFocus: Bool = true) {
        guard let panel else { return }
        let closing = onClose
        self.panel = nil
        key = nil
        onClose = nil
        unwatch()
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if restoringFocus { parent?.makeKey() }
        closing?()
    }

    private var storedTextSize: Int {
        UserDefaults.standard.object(forKey: InterfaceKey.textSize) as? Int ?? InterfaceStyle.defaultTextSize
    }

    private func layoutSoon() {
        guard !layoutPending else { return }
        layoutPending = true
        DispatchQueue.main.async { [weak self] in
            self?.layoutPending = false
            self?.layout()
        }
    }

    private func layout() {
        guard let panel, let parent, let anchor, let target = anchor.screenRect(of: nil) else { return }
        var visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? target.insetBy(dx: -400, dy: -400)
        let inside = parent.frame.insetBy(dx: 8, dy: 0)
        let minX = max(visible.minX, inside.minX)
        visible = CGRect(x: minX, y: visible.minY, width: min(visible.maxX, inside.maxX) - minX, height: visible.height)
        let placement = ValuePanelFrame.placement(
            anchor: target, visible: visible, contentHeight: height, floor: width, ceiling: width, gap: ValueEditMetrics.gap, fitting: width)
        if panel.frame != placement.frame {
            panel.setFrame(placement.frame, display: true)
            panel.invalidateShadow()
        }
        panel.contentView?.frame = NSRect(origin: .zero, size: placement.frame.size)
    }

    private func watch() {
        appearanceWatch = parent?.observe(\.effectiveAppearance) { [weak self] window, _ in
            MainActor.assumeIsolated { self?.panel?.appearance = window.effectiveAppearance }
        }
        let center = NotificationCenter.default
        if let parent {
            observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layoutSoon() }
            })
            for name in [NSWindow.didResizeNotification, NSWindow.willCloseNotification, NSWindow.didEndLiveResizeNotification] {
                observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismiss(restoringFocus: false) }
                })
            }
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoringFocus: false) }
        })
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? false } ? nil : event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoringFocus: false) }
        }) { monitors.append(monitor) }
    }

    private func unwatch() {
        appearanceWatch = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// Whether the panel took the event, which then goes no further.
    private func handle(_ event: NSEvent) -> Bool {
        guard let panel else { return false }
        if event.type == .keyDown {
            guard event.window === panel, event.keyCode == 53 else { return false }
            dismiss()
            return true
        }
        if event.window !== panel {
            if let key { closedByClick = (key, .now) }
            dismiss(restoringFocus: false)
        }
        return false
    }
}
