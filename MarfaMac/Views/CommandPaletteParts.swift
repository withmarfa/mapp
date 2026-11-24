import SwiftUI

/// One row of the command palette: a command, a place or an item.
struct PaletteEntry: Identifiable {
    var id: String
    let title: String
    /// The type's name for an item, at the row's right.
    var detail: String?
    /// The words a search shows under the title where it has no excerpt: the item's text, or its type and collections.
    var snippet: String?
    /// The words around what a search found.
    var excerpt: SearchExcerpt?
    /// A search's date, at the row's right in place of the detail.
    var date: String?
    let icon: RowIcon
    var shortcut: String?
    /// Set for an item, which Actions offers more for than a command.
    var item: ItemID?
    /// Another interface takes the keyboard itself, so the page should not regain focus first.
    var takesFocus = false
    /// The menu group ⌘K lists it under with nothing typed; nil for a command only typing finds.
    var group: PaletteSections.CommandGroup? = .file
    let action: () -> Void
}

/// The grey of a chosen row: quiet in light and in dark, with the text keeping its own color.
private let paletteSelection = Color.primary.opacity(0.1)

/// The palette's columns, shared by the field and the rows so the typed words start where the titles do.
enum PaletteMetrics {
    /// The list's inset from the panel's edge.
    static let listInset: CGFloat = 6
    /// A row's inset inside the list.
    static let rowInset: CGFloat = 8
    /// The mark column's left edge, from the panel's edge.
    static let markInset: CGFloat = listInset + rowInset
    static let markWidth: CGFloat = 20
    static let markGap: CGFloat = 10
    /// The tallest the results grow, the filter row included; the bar adds its own height under them.
    static let resultsHeight: CGFloat = 460
    /// The results' height with nothing found, so the palette is about 400 points tall with its field: taller than a
    /// line of text asks for, and shorter than a full list.
    static let emptyResultsHeight: CGFloat = 302
}

/// The bar at the foot of the results, which rows scroll under: the filter button in Search Items, and Open and Actions.
enum PaletteBar {
    static let inset: CGFloat = 10
    static let spacing: CGFloat = 8
    /// The label size of the bar's controls, a point larger than a large control's.
    static let fontSize: CGFloat = 14
    /// The bar's height: a large glass button's, for a label a point larger than a large control's.
    static let height: CGFloat = 31
    /// How far a segment's fill, or the filter button's, sits inside its capsule.
    static let fillInset: CGFloat = 3
    static let grow = Animation.snappy(duration: 0.18)
}

struct PaletteSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .interfaceFont(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, PaletteMetrics.rowInset)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A type's mark in its tone, or a command's symbol.
private struct PaletteMark: View {
    let icon: RowIcon

    var body: some View {
        Group {
            switch icon {
            case .type(let name):
                TypeMark(icon: name, size: .side)
            case .symbol:
                RowIconImage(icon: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: PaletteMetrics.markWidth, height: PaletteMetrics.markWidth)
            }
        }
        .frame(width: PaletteMetrics.markWidth)
        .accessibilityHidden(true)
    }
}

struct PaletteRow: View {
    let entry: PaletteEntry
    let query: String
    let isHighlighted: Bool
    /// Search Items shows two lines on every row, so its rows are all one height: the title, then the words around the
    /// match or the item's own words. The command palette's rows, commands among them, all take one line.
    let isSearch: Bool
    /// Whether a search row shows the words around the match (Show Snippets); without them it takes one line.
    var showsSnippets = true
    let onHover: () -> Void
    let onRun: () -> Void

    var body: some View {
        let words = isSearch && showsSnippets ? (entry.excerpt?.attributed() ?? AttributedString(entry.snippet ?? " ")) : nil
        // A row with a second line keeps its mark and date on the title's line, as a one-line row has them.
        HStack(alignment: words == nil ? .center : .firstTextBaseline, spacing: PaletteMetrics.markGap) {
            PaletteMark(icon: entry.icon)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                titleText
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let words {
                    Text(words)
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trailing = isSearch ? entry.date : entry.detail {
                Text(trailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            } else if let shortcut = entry.shortcut {
                ShortcutKeys(shortcut)
            }
        }
        .padding(.horizontal, PaletteMetrics.rowInset)
        .padding(.vertical, words == nil ? 5 : 6)
        .background(isHighlighted ? paletteSelection : .clear, in: .rect(cornerRadius: 8, style: .continuous))
        .contentShape(.rect)
        .onContinuousHover { phase in
            if case .active = phase { onHover() }
        }
        .onTapGesture(perform: onRun)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }

    /// The title with the typed words in bold.
    private var titleText: Text {
        var title = AttributedString(entry.title)
        if let range = PaletteMatch.matchRange(in: entry.title, query), let target = Range(range, in: title) {
            title[target].inlinePresentationIntent = .stronglyEmphasized
        }
        return Text(title)
    }
}

/// Open and Actions as one glass capsule of the bar's height with two segments, as the toolbar groups its buttons:
/// pointing at a segment fills only that segment.
struct PaletteFooter: View {
    let openTitle: String
    let onOpen: () -> Void
    /// The key caps beside Actions, as the person has set them; nil when Palette Actions has no shortcut.
    let actionsKeys: String?
    /// Nil where there is nothing to act on, as when nothing was found and the bar only offers New Item.
    let onActions: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Text(openTitle)
                    ShortcutKeys("↩")
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("CommandPaletteOpen")
            if let onActions {
                Button(action: onActions) {
                    HStack(spacing: 6) {
                        Text("Actions")
                        if let actionsKeys {
                            ShortcutKeys(actionsKeys)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityIdentifier("CommandPaletteActions")
            }
        }
        .buttonStyle(PaletteSegmentStyle())
        .font(.system(size: PaletteBar.fontSize))
        .padding(PaletteBar.fillInset)
        .frame(height: PaletteBar.height)
        .glassEffect(.regular, in: .capsule)
    }
}

/// A segment of the bar's capsule: a soft fill while the pointer is over it, and a deeper one while it is pressed.
private struct PaletteSegmentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Segment(configuration: configuration)
    }

    private struct Segment: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
                .background(.primary.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.1 : 0), in: .capsule)
                .contentShape(.capsule)
                .onHover { isHovered = $0 }
        }
    }
}

/// The last line of Search Items' results when what is left out of search matches too: how many more matched there, and
/// Show, which searches once more with nothing left out.
struct PaletteLeftOutLine: View {
    let text: String
    let show: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().padding(.vertical, 6)
            HStack(spacing: PaletteMetrics.markGap) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.tertiary)
                    .frame(width: PaletteMetrics.markWidth)
                Text(text)
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button("Show", action: show)
                    .appButton(.secondary, size: .small)
                    .accessibilityLabel(Text("Show Matches Left Out of Search"))
                    .accessibilityIdentifier("CommandPaletteShowLeftOut")
            }
            .padding(.horizontal, PaletteMetrics.rowInset)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("CommandPaletteLeftOut")
    }
}

/// The glass button at the bar's left in Search Items that shows and hides the filter row. With filters set, it shows
/// their number beside its symbol and a soft fill inside its glass, in the bar's own neutral color.
struct PaletteFilterButton: View {
    let count: Int
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                if count > 0 { Text(count, format: .number) }
            }
            .font(.system(size: PaletteBar.fontSize))
            .padding(.horizontal, count > 0 ? 9 : 0)
            .frame(minWidth: PaletteBar.height, minHeight: PaletteBar.height)
            .background {
                if count > 0 {
                    Capsule().fill(.primary.opacity(0.12)).padding(PaletteBar.fillInset)
                }
            }
            .contentShape(.capsule)
            // Drawn here, since the glass button style pads an icon out to a wide pill: as tall and as round as the
            // capsule beside it, but only as wide as it is tall.
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(isOn ? "Hide Filters" : "Show Filters")
        .accessibilityValue(count > 0 ? Text("\(count) set") : Text(""))
        .accessibilityIdentifier("CommandPaletteFilters")
    }
}

/// What the palette's filters hold and the panel open for one of them. A class, so the panels, which open in windows of
/// their own, read and change the same state the palette draws.
@MainActor @Observable
final class PaletteFilterState {
    var filters = PaletteFilters()
    /// The field whose panel is open, which keeps its chip in the row while it has no value yet.
    var openField: PaletteFilters.Field?
}

/// The row under the field that holds the filters' chips and the +, which are a view's filter row (`FilterChipsBar`)
/// with the palette's three fields.
struct PaletteFilterRow: View {
    @CurrentLibrary private var library
    let state: PaletteFilterState
    @State private var anchors = FilterChipAnchors()

    var body: some View {
        FilterChipsBar(
            chips: chips, leadingInset: PaletteMetrics.markInset, showsHelp: false, anchors: anchors,
            open: { id in PaletteFilters.Field(rawValue: id).map(openValues) },
            remove: { id in if let field = PaletteFilters.Field(rawValue: id) { remove(field) } },
            add: openFields
        )
        .onDisappear { FilterPanelPresenter.shared.dismiss(restoringFocus: false) }
        .accessibilityIdentifier("CommandPaletteFilterRow")
    }

    private var chips: [FilterChipItem] {
        PaletteFilters.Field.allCases.compactMap { field in
            guard state.filters.isSet(field) || state.openField == field else { return nil }
            return FilterChipItem(
                id: field.rawValue, field: field.title,
                relation: state.filters.negated.contains(field) ? String(localized: "is not") : String(localized: "is"),
                values: PaletteFilterOptions(library: library).chosen(in: state.filters, for: field).map(\.title).joined(separator: ", "))
        }
    }

    private func remove(_ field: PaletteFilters.Field) {
        if state.openField == field { FilterPanelPresenter.shared.dismiss(restoringFocus: false) }
        state.filters.clear(field)
    }

    private func openValues(_ field: PaletteFilters.Field) {
        state.openField = field
        FilterPanelPresenter.shared.present(
            key: field.rawValue, anchor: anchors.view(for: field.rawValue), width: 280, onClose: { state.openField = nil }
        ) {
            PaletteFilterValueHost(state: state, field: field).environment(\.library, library)
        }
        // The click that closed this panel asked to open it again: it stays closed.
        if !FilterPanelPresenter.shared.isOpen(for: field.rawValue) { state.openField = nil }
    }

    private func openFields() {
        let fields = PaletteFilters.Field.allCases.filter { !state.filters.isSet($0) && state.openField != $0 }.map {
            FilterFieldOption(id: $0.rawValue, title: $0.title, symbol: $0.symbol)
        }
        FilterPanelPresenter.shared.present(key: FilterChipAnchors.addKey, anchor: anchors.view(for: FilterChipAnchors.addKey), width: 240, onClose: {}) {
            FilterFieldPanel(fields: fields) { id in
                FilterPanelPresenter.shared.dismiss(restoringFocus: false)
                guard let field = PaletteFilters.Field(rawValue: id) else { return }
                state.openField = field
                anchors.whenShown(field.rawValue) { openValues(field) }
            }
        }
    }
}

extension PaletteFilters.Field {
    var title: String {
        switch self {
        case .type: String(localized: "Type")
        case .collection: String(localized: "Collection")
        case .updated: String(localized: "Updated")
        }
    }

    var symbol: String {
        switch self {
        case .type: "square.grid.2x2"
        case .collection: "rectangle.stack"
        case .updated: "calendar"
        }
    }
}

extension PaletteFilters.Period {
    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .thisWeek: String(localized: "This Week")
        case .thisMonth: String(localized: "This Month")
        case .thisYear: String(localized: "This Year")
        }
    }
}

/// The values each field offers in the library as it is now.
private struct PaletteFilterOptions {
    let library: any ItemLibrary

    func all(for field: PaletteFilters.Field) -> [FilterValueOption] {
        switch field {
        case .type:
            // The type's own name, as a table's Type column says it; the sidebar's longer label only where two types share one.
            let counts = library.itemTypeCounts
            let names = counts.map { library.catalogue.label(for: $0.id) }
            return zip(counts, names).map { count, name in
                FilterValueOption(id: count.id.rawValue, title: names.filter { $0 == name }.count > 1 ? count.label : name, mark: .type(icon: count.icon))
            }
        case .collection:
            return library.collections.map {
                FilterValueOption(id: $0.id.rawValue, title: $0.displayTitle, mark: .type(icon: library.catalogue.icon(for: $0.type)))
            }
        case .updated:
            return PaletteFilters.Period.allCases.map { FilterValueOption(id: $0.rawValue, title: $0.title, mark: .symbol("calendar")) }
        }
    }

    /// The values the filter holds that the library still has.
    func chosen(in filters: PaletteFilters, for field: PaletteFilters.Field) -> [FilterValueOption] {
        let held: Set<String> = switch field {
        case .type: Set(filters.types.map(\.rawValue))
        case .collection: Set(filters.collections.map(\.rawValue))
        case .updated: filters.period.map { [$0.rawValue] } ?? []
        }
        return all(for: field).filter { held.contains($0.id) }
    }
}

/// A field's value panel, read from the palette's filters as they are now, so a pick shows in it at once.
private struct PaletteFilterValueHost: View {
    @CurrentLibrary private var library
    let state: PaletteFilterState
    let field: PaletteFilters.Field

    var body: some View {
        let options = PaletteFilterOptions(library: library)
        let chosen = options.chosen(in: state.filters, for: field)
        let held = Set(chosen.map(\.id))
        FilterValuePanel(
            field: field.title,
            isNegated: state.filters.negated.contains(field),
            chosen: chosen.map { ValueChip(id: $0.id, title: $0.title, mark: $0.mark) },
            options: options.all(for: field).filter { !held.contains($0.id) },
            setNegated: { isNegated in
                if isNegated { state.filters.negated.insert(field) } else { state.filters.negated.remove(field) }
            },
            add: add,
            remove: remove
        )
    }

    private func add(_ id: String) {
        switch field {
        case .type: state.filters.types.insert(TypeID(id))
        case .collection: state.filters.collections.insert(ItemID(rawValue: id))
        case .updated: state.filters.period = PaletteFilters.Period(rawValue: id)
        }
    }

    private func remove(_ id: String) {
        switch field {
        case .type: state.filters.types.remove(TypeID(id))
        case .collection: state.filters.collections.remove(ItemID(rawValue: id))
        case .updated: state.filters.period = nil
        }
        if !state.filters.isSet(field) { state.filters.negated.remove(field) }
    }
}

/// Where the palette's keyboard is: its own field, or the Actions panel's.
enum PaletteFocus: Hashable {
    case field, actions
}

/// What can be done to the chosen row: a panel grown out of the bar with the row's title, its actions, and a
/// field that narrows them. Escape puts the panel away and leaves the palette.
struct PaletteActionsPanel: View {
    let title: String
    let actions: [PaletteAction]
    let perform: (PaletteAction) -> Void
    /// Return in the field: reads the highlight when it is pressed, not when the view was last drawn.
    let submit: () -> Void
    let close: () -> Void
    @Binding var query: String
    @Binding var highlighted: Int
    var focus: FocusState<PaletteFocus?>.Binding

    var body: some View {
        let shown = PaletteAction.filtered(actions, by: query)
        let chosen = min(highlighted, max(shown.count - 1, 0))
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .interfaceFont(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(shown.indices, id: \.self) { index in
                    let action = shown[index]
                    if action.isDestructive, index > 0 {
                        Divider().padding(.vertical, 4)
                    }
                    row(action, isHighlighted: index == chosen)
                        .onContinuousHover { phase in
                            if case .active = phase, highlighted != index { highlighted = index }
                        }
                        .onTapGesture { perform(action) }
                }
                if shown.isEmpty {
                    Text("No Actions")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
            Divider().padding(.top, 6)
            TextField("Search for Actions…", text: $query)
                .textFieldStyle(.plain)
                .focused(focus, equals: .actions)
                .onSubmit(submit)
                .onExitCommand(perform: close)
                .padding(.horizontal, 12)
                .padding(.vertical, 13)
                .accessibilityIdentifier("CommandPaletteActionsField")
        }
        .frame(width: 300)
        .nestedPanelSurface(cornerRadius: 16)
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            focus.wrappedValue = .actions
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions")
    }

    private func row(_ action: PaletteAction, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .frame(width: 18)
                .foregroundStyle(action.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            Text(action.title)
                .foregroundStyle(action.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(action.keys, id: \.self) { KeyCap(key: $0) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHighlighted ? paletteSelection : .clear, in: .rect(cornerRadius: 8, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }

    /// The actions that have a shortcut of their own. While Actions is open the palette owns every one of these keys,
    /// for a row that does not offer the action too, so none reaches the window's menu.
    static let shortcutKinds: [PaletteAction.Kind] = [.openInNewWindow, .copyLink, .versionHistory, .delete]

    /// The action's own shortcut, which the key caps beside it show.
    static func shortcut(of kind: PaletteAction.Kind) -> KeyboardShortcut? {
        switch kind {
        case .openInNewWindow: KeyboardShortcut(.return, modifiers: .command)
        case .copyLink: KeyboardShortcut("c", modifiers: [.command, .shift])
        case .versionHistory: KeyboardShortcut("y", modifiers: [.command, .option])
        case .delete: KeyboardShortcut(.delete, modifiers: .command)
        default: nil
        }
    }
}
