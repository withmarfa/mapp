import AppKit
import Marfa
import MarfaIcons
import SwiftUI

extension View {
    /// The room a table's cell keeps around its content, which the item table and the index tables share so their rows
    /// are one height: the content is at least 22 points, centered, with 3 points above and below it, and with the
    /// table's own room beyond that a row is 36 points, as the board draws it.
    func tableCellRoom(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, minHeight: 22, maxHeight: .infinity, alignment: alignment)
            .padding(.vertical, 3)
    }
}

/// One cell of the table. A value a person picks, such as a status or a priority, is a menu that changes it in place;
/// anything else is shown as it reads, and edited on the item's page or in Details.
///
/// The library is handed in rather than read from the environment: the table lays out its cells in views of its own,
/// which do not always have the window's environment yet.
struct ItemTableCell: View {
    @Environment(\.undoManager) private var undoManager
    let library: any ItemLibrary
    let row: ItemTableRow
    let column: ItemTableColumn
    let browser: Browser
    let order: ItemOrder
    let dateFormat: DateFormat
    /// Which row the pointer is on, shared by the row's cells, so the name's cell can answer to it from any of them.
    let hover: ItemTableHover
    /// Set on the last column shown, where the row's quick actions stand while the pointer is on the row.
    var endsRow = false
    @State private var isHovering = false
    @State private var anchor = ValueEditAnchorBox()

    /// How far the table's own cell reaches past the content on each side, measured from the cell itself. A hover tint
    /// reaches out by it, so the tint fills the cell to its edges; the content is padded in by the same amount, and the
    /// cell's control is pulled back out, so the content keeps the column's text edge.
    @State private var bleed = CellBleed.zero
    /// The row's quick actions, shown in place of what the row's last cell holds while the pointer is on the row.
    private var showsQuickActions: Bool { endsRow && hover.row == row.id && !browser.quickActions.isEmpty }

    var body: some View {
        content
            .opacity(showsQuickActions ? 0 : 1)
            .overlay(alignment: .trailing) {
                if showsQuickActions { RowQuickActions(id: row.id, actions: browser.quickActions) }
            }
            .lineLimit(1)
            // The same room for every cell, whether or not it offers an edit, so the probe measures the same frame throughout.
            .tableCellRoom()
            .background { if offersEdit { CellBleedProbe(bleed: $bleed) } }
            // One anchor for a field's cell however it reads, so a panel opened from it outlives the first value written.
            .background {
                if isField {
                    ValueEditAnchor(box: anchor)
                        .padding(.horizontal, -bleed.horizontal)
                        .padding(.vertical, -bleed.vertical)
                }
            }
            // The name cell can request counts even while an empty count column is hidden.
            .background {
                if case .title = column.content {
                    Color.clear.wantsCounts(of: row.id, browser.looks(in: library)[row.item.type]?.countQueries ?? [], in: library.counts)
                }
            }
            .onHover { setHovering($0) }
            .onDisappear { setHovering(false) }
            // A panel laid over the table gets the pointer and sends no exit to the cell beneath it.
            .onChange(of: hover.epoch) { isHovering = false }
            // A cell may be reused for another row while the pointer is over it; the old row must not keep its arrow.
            .onChange(of: row.id) { old, _ in
                if isHovering { hover.exit(old) }
                isHovering = false
            }
    }

    /// The cell's field as the row's own type declares it.
    private var rowField: ItemTypeInfo.Field? { column.field(for: row, catalogue: library.catalogue) }

    private var isField: Bool {
        if case .field = column.content { true } else { false }
    }

    /// Whether the cell is a value picked from a menu that this row's own field declares and that can be changed.
    private var offersPicker: Bool {
        guard let rowField, row.item.obstacle(toField: rowField.key) == nil else { return false }
        return column.picksFrom(rowField)
    }

    /// The panel an empty cell opens to take a first value, where its property can be edited for this item.
    private var addKind: ValueEditKind? { column.addKind(for: row, catalogue: library.catalogue) }

    /// Whether the cell offers to change or add a value, which its hover tint shows.
    private var offersEdit: Bool { offersPicker || addKind != nil }

    private func setHovering(_ inside: Bool) {
        guard inside != isHovering else { return }
        isHovering = inside
        if inside { hover.enter(row.id) } else { hover.exit(row.id) }
    }

    @ViewBuilder private var content: some View {
        switch column.content {
        case .title: title
        case .type: MarkedName(text: row.typeLabel, icon: row.typeIcon, size: .row)
        case .parent: links(row.parent.map { [$0] } ?? [])
        case .children: links(row.children)
        case .collections: links(row.collections)
        case .created: date(row.item.created, hasTime: true, isDue: false)
        case .edited: date(row.item.modified, hasTime: true, isDue: false)
        case .occurred: date(row.item.occurred ?? row.item.created, hasTime: true, isDue: false)
        case .tags: tags
        case .source:
            // Read live, since the server names a source after the rows were made.
            Text(verbatim: row.item.source.flatMap { $0.isEmpty ? nil : library.sources.name($0) } ?? "").foregroundStyle(.secondary)
        case .count(let fact): count(fact)
        case .duration(let start, let end):
            if let seconds = ItemTableValue.duration(row, start: start, end: end) {
                Text(Duration.seconds(seconds), format: .units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        // A mixed table's column holds the words of every type; each cell offers its own row's type's.
        case .field(let field):
            if let kind = addKind { add(kind) } else { value(of: rowField ?? field) }
        }
    }

    /// A count Marfa answered, as a row says it, with the help tag that splits it. A count with nothing to say draws nothing.
    @ViewBuilder private func count(_ fact: CountFact) -> some View {
        let answer = row.counts[fact]
        let hasStatus = library.catalogue.itemTypes[row.item.type]?.statusField != nil
        if let text = CountWording.text(of: fact, answer: answer, hasStatus: hasStatus) {
            Text(verbatim: text).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                .help(CountWording.help(of: fact, answer: answer) ?? "")
        }
    }

    /// An empty cell of a value a panel edits: on hover it reads as empty and fills with the tint, and a click opens the
    /// panel under it, as the value's row does on the page.
    private func add(_ kind: ValueEditKind) -> some View {
        Button {
            let id = row.id
            let library = library
            let undoManager = undoManager
            var request = ValueEditRequest(kind: kind, library: library, item: id, undoManager: undoManager)
            request.write = { value in
                guard let key = kind.field?.key else { return false }
                return library.setItemProperty(id, key: key, value: value, undoManager: undoManager)
            }
            guard let view = anchor.view else { return }
            ValueEditPresenter.shared.present(request, anchor: view)
            // The panel takes the pointer without sending the cell an exit.
            hover.clear()
        } label: {
            offering(HStack(spacing: 4) {
                if isHovering { Text("Empty").foregroundStyle(.tertiary) }
                Spacer(minLength: 0)
            })
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .padding(.horizontal, -bleed.horizontal)
        .padding(.vertical, -bleed.vertical)
        .accessibilityLabel(Text(kind.field?.label ?? ""))
        .accessibilityValue(Text("Not Set"))
        .accessibilityHint(Text("Opens a panel to add a value"))
    }

    /// A control's label as the cell offers it: the whole cell, tinted under the pointer.
    private func offering(_ label: some View) -> some View {
        label
            .padding(.horizontal, bleed.horizontal)
            .padding(.vertical, bleed.vertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            .contentShape(.rect)
    }

    // MARK: The name

    private var title: some View {
        HStack(spacing: 8) {
            Text(row.item.displayTitle)
                .fontWeight(.medium)
                .foregroundStyle(row.item.isUntitled ? .secondary : .primary)
                .truncationMode(.tail)
            // A list of both tiers says which items are the Feed's.
            if row.item.tier == .feed, browser.listing.scope == .all { FeedMark() }
            if row.item.isFavorite {
                Image(systemName: "star.fill")
                    .imageScale(.small)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { openButton }
    }

    /// Notion's Open, laid over the end of the name: a click opens the page, where selecting the row would only show
    /// it in Details. It shows on the row under the pointer and on the one selected row, and is there for
    /// assistive technology and clicks only then.
    private var openButton: some View {
        let isShown = hover.row == row.id || (browser.selection.count == 1 && browser.selection.contains(row.id))
        return Button {
            browser.open([row.id])
        } label: {
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Open"))
        .help(Text("Open"))
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(isShown)
        .animation(.easeOut(duration: 0.1), value: isShown)
    }

    // MARK: Values

    @ViewBuilder private func value(of field: ItemTypeInfo.Field) -> some View {
        let current = ItemTableValue.string(row, key: field.key)
        let declares = library.catalogue.itemTypes[row.item.type]?.declares(field.key) ?? false
        let editable = declares && row.item.obstacle(toField: field.key) == nil
        switch column.style(for: field) {
        case .status, .priority, .choice:
            picked(field, current: current, editable: editable)
        case .boolean:
            let isOn: Bool = if case .bool(let flag)? = row.item.value(of: field.key) { flag } else { false }
            if declares {
                Toggle(field.label, isOn: Binding { isOn } set: { set(field, .bool($0)) })
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!editable)
            }
        case .date:
            if let current {
                // A field's date is a day, even with a time: a task due at four today is due Today.
                if let parsed = ItemDate.parse(current) {
                    date(parsed.date, hasTime: false, isDue: library.catalogue.isDueDate(field, of: row.item.type))
                } else {
                    Text(current).foregroundStyle(.secondary)
                }
            }
        case .number:
            if let current { Text(current).monospacedDigit() }
        default:
            other(field, current: current)
        }
    }

    /// The row's tags, as the page's tag chips; the rest are counted.
    @ViewBuilder private var tags: some View {
        let tags = row.item.tags.subtracting([ItemTag.favorite]).sorted()
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags.prefix(RowContent.shownTags), id: \.self) { PageChip(text: $0, kind: .tag, size: .row) }
                if tags.count > RowContent.shownTags { Text(verbatim: "+\(tags.count - RowContent.shownTags)").foregroundStyle(.secondary) }
            }
        }
    }

    /// A value that is not picked from a fixed set: people as their initials and name, a list of words as choices, anything else
    /// as plain text with no label.
    @ViewBuilder private func other(_ field: ItemTypeInfo.Field, current: String?) -> some View {
        switch PropertyRow.value(of: field, in: row.item, format: dateFormat) {
        case .people(let names)?:
            HStack(spacing: 3) {
                ForEach(Array(names.prefix(Self.shownPeople).enumerated()), id: \.offset) { _, name in
                    PagePerson(name: name, initials: PersonInitials.of(name), size: .row, showsName: true)
                }
                if names.count > Self.shownPeople { Text(verbatim: "+\(names.count - Self.shownPeople)").foregroundStyle(.secondary) }
            }
        case .options(let words)?:
            let tones = PropertyRow.optionTones(of: field, in: row.item, isPriority: library.catalogue.isPriority(field, of: row.item.type))
            HStack(spacing: 4) {
                ForEach(Array(words.prefix(Self.shownOptions).enumerated()), id: \.offset) { index, word in
                    PageChip(text: word, kind: .option(tones.indices.contains(index) ? tones[index] : OptionTone.tone(for: word)), size: .row)
                }
                if words.count > Self.shownOptions { Text(verbatim: "+\(words.count - Self.shownOptions)").foregroundStyle(.secondary) }
            }
        default:
            if case .list(let shape) = field.kind, let stored = row.item.value(of: field.key), InspectorFields.hasValue(stored) {
                Text(shape.display(of: stored)).foregroundStyle(.secondary).truncationMode(.tail)
            } else if let current {
                Text(current).foregroundStyle(.secondary).truncationMode(.tail)
            }
        }
    }

    private static let shownPeople = 3
    private static let shownOptions = 2

    /// A picked value as the page's own chip at row size: a status's symbol in its chip, any other word with a dot.
    @ViewBuilder private func chip(_ value: String, field: ItemTypeInfo.Field) -> some View {
        let label = ItemTypeInfo.Field.label(ofOption: value)
        if column.style == .status {
            PageChip(text: label, kind: .status(StatusSymbol(group: field.statusGroup(of: value))), size: .row)
        } else {
            PageChip(
                text: label,
                kind: .option(OptionTone.tone(of: value, in: field, isPriority: column.style == .priority)), size: .row)
        }
    }

    /// A value from a fixed set: a menu of the others where it can be changed, the value alone where it cannot.
    @ViewBuilder private func picked(_ field: ItemTypeInfo.Field, current: String?, editable: Bool) -> some View {
        if editable, column.style(for: field) == .status {
            statusButton(field, current: current)
        } else if editable {
            picker(field, current: current)
        } else if let current {
            chip(current, field: field)
        }
    }

    /// A value picked from the field's options, as the cell shows it, opening a menu of the others.
    private func picker(_ field: ItemTypeInfo.Field, current: String?) -> some View {
        Menu {
            Picker(field.label, selection: Binding { current ?? "" } set: { set(field, $0.isEmpty ? nil : .string($0)) }) {
                ForEach(field.options(including: current), id: \.self) { option in
                    ItemTableMenuLabel(column: column, value: option, title: ItemTypeInfo.Field.label(ofOption: option))
                        .tag(option)
                }
                Divider()
                Text("Not Set").tag("")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            offering(HStack(spacing: 4) {
                if let current {
                    chip(current, field: field)
                } else if isHovering {
                    Text("Empty").foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            })
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .padding(.horizontal, -bleed.horizontal)
        .padding(.vertical, -bleed.vertical)
        .accessibilityLabel(Text(field.label))
        .accessibilityValue(Text(current.map(ItemTypeInfo.Field.label(ofOption:)) ?? String(localized: "Not Set")))
    }

    /// A status as the cell shows it, which opens the status panel under it, as a status does wherever it is seen.
    private func statusButton(_ field: ItemTypeInfo.Field, current: String?) -> some View {
        Button {
            guard let view = anchor.view else { return }
            // The panel takes the pointer without sending the cell an exit.
            hover.clear()
            StatusPanel.open(row.id, in: library, undoManager: undoManager, under: view)
        } label: {
            offering(HStack(spacing: 4) {
                if let current {
                    chip(current, field: field)
                } else if isHovering {
                    Text("Empty").foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            })
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .padding(.horizontal, -bleed.horizontal)
        .padding(.vertical, -bleed.vertical)
        .accessibilityLabel(Text(field.label))
        .accessibilityValue(Text(current.map(ItemTypeInfo.Field.label(ofOption:)) ?? String(localized: "Not Set")))
        .accessibilityHint(Text("Opens a panel to change the status"))
    }

    private func set(_ field: ItemTypeInfo.Field, _ value: PropertyValue?) {
        library.setItemProperty(row.id, key: field.key, value: value, undoManager: undoManager)
    }

    /// Linked items as the page's linked-item chips, the first two and then the rest counted. A chip shows its item.
    @ViewBuilder private func links(_ items: [RelatedItem]) -> some View {
        if !items.isEmpty {
            HStack(spacing: 4) {
                ForEach(items.prefix(RowContent.shownLinks)) { link in
                    Button {
                        if let item = library.item(link.id) { browser.reveal(item, in: library, order: order) }
                    } label: {
                        MarkedName(text: link.title, icon: link.icon, size: .row, underlinesOnHover: true)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Show \(link.title)"))
                }
                if items.count > RowContent.shownLinks {
                    Text(verbatim: "+\(items.count - RowContent.shownLinks)").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A day as people say it: Today, Yesterday, a weekday this week, then the date, and, for the item's own stamps, the time of one that is today.
    /// A due date already past, on work not finished, is red.
    private func date(_ date: Date, hasTime: Bool, isDue: Bool) -> some View {
        let now = library.now()
        let isLate = isDue && date < Calendar.current.startOfDay(for: now)
            && library.catalogue.statusGroup(of: row.item)?.isFinished != true
        return Text(DateDisplay.text(of: date, hasTime: hasTime, place: .table, format: dateFormat, now: now))
            .foregroundStyle(isLate ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .monospacedDigit()
    }
}

/// A category's mark and name in a group's header and in a menu: a status's symbol, a priority's dot, or the name
/// alone. A cell draws the page's own chips instead (`ItemTableCell`).
struct ItemTableCategory: View {
    let column: ItemTableColumn
    let value: String?
    let title: String
    /// Whether `value` names a group of a status column, as a group's header does, and not a status word.
    var isGroup = false

    var body: some View {
        switch column.style {
        case .status:
            Label {
                Text(title)
            } icon: {
                StatusMark(group: statusGroup)
            }
            .labelStyle(ItemTableLabelStyle())
        case .priority:
            Label {
                Text(title).foregroundStyle(value == nil ? .secondary : .primary)
            } icon: {
                if let value, let field = column.field { OptionDot(tone: OptionTone.tone(of: value, in: field, isPriority: true)) }
            }
            .labelStyle(ItemTableLabelStyle())
        default:
            Text(title)
        }
    }

    private var statusGroup: StatusGroup? {
        guard let value else { return nil }
        if isGroup { return StatusBucket(id: value).flatMap { if case .group(let group) = $0 { group } else { nil } } }
        return column.field?.statusGroup(of: value)
    }
}

/// A category as a menu item: a menu shows images but not views, so a status's symbol is drawn into one.
struct ItemTableMenuLabel: View {
    let column: ItemTableColumn
    let value: String?
    let title: String

    var body: some View {
        if column.style == .status {
            Label { Text(title) } icon: { Self.symbol(for: value.flatMap { column.field?.statusGroup(of: $0) }) }
        } else {
            ItemTableCategory(column: column, value: value, title: title)
        }
    }

    private static func symbol(for group: StatusGroup?) -> Image {
        let renderer = ImageRenderer(content: StatusMark(group: group).padding(1))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage.map { Image(nsImage: $0) } ?? Image(systemName: "circle")
    }
}

/// A choice's dot, in the color of its tone.
private struct OptionDot: View {
    let tone: TypeTone
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Circle().fill(tone.color(for: scheme)).frame(width: 8, height: 8).accessibilityHidden(true)
    }
}

/// An icon and title closer together than a list's, as a cell's content.
struct ItemTableLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.frame(minWidth: 14)
            configuration.title
        }
    }
}

/// Which table row the pointer is on. Every cell of a row reports when the pointer enters or leaves it, and a pointer
/// crossing from one cell to the next is on the row throughout, so the row is let go of only after a moment with no
/// cell of it hovered.
@MainActor @Observable
final class ItemTableHover {
    private(set) var row: ItemID?
    /// Counts the times every cell was told to forget the pointer, which each cell reads to drop its own state.
    private(set) var epoch = 0
    private var cells: [ItemID: Int] = [:]
    private var release: Task<Void, Never>?
    private let grace: Duration

    init(grace: Duration = .milliseconds(60)) { self.grace = grace }

    func enter(_ id: ItemID) {
        cells[id, default: 0] += 1
        release?.cancel()
        row = id
    }

    /// Forgets the pointer, as when a panel opens over the table: the cells beneath it are sent no exit.
    func clear() {
        release?.cancel()
        cells = [:]
        row = nil
        epoch += 1
    }

    func exit(_ id: ItemID) {
        let remaining = (cells[id] ?? 1) - 1
        cells[id] = remaining > 0 ? remaining : nil
        guard remaining <= 0, row == id else { return }
        release?.cancel()
        release = Task { [grace] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled, cells[id] == nil, row == id else { return }
            row = nil
        }
    }
}

/// How far a table cell reaches past its content, in points.
struct CellBleed: Equatable {
    var horizontal: CGFloat
    var vertical: CGFloat
    static let zero = CellBleed(horizontal: 0, vertical: 0)
}

/// Measures the table's cell around the view it is laid behind, so a tint can fill the cell exactly.
private struct CellBleedProbe: NSViewRepresentable {
    @Binding var bleed: CellBleed

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        view.report = { measured in
            if measured != bleed { bleed = measured }
        }
    }

    final class Probe: NSView {
        var report: ((CellBleed) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

        private func measure() {
            guard window != nil, bounds.width > 0 else { return }
            var ancestor = superview
            while let view = ancestor, !(view.superview is NSTableRowView) { ancestor = view.superview }
            guard let cell = ancestor, let row = cell.superview as? NSTableRowView,
                let table = row.superview as? NSTableView else { return }
            let column = table.column(for: cell)
            guard column >= 0 else { return }
            let own = table.convert(bounds, from: self)
            let reach = table.rect(ofColumn: column).intersection(row.frame)
            let measured = CellBleed(
                horizontal: max(0, min(own.minX - reach.minX, reach.maxX - own.maxX)).rounded(),
                vertical: max(0, min(own.minY - reach.minY, reach.maxY - own.maxY)).rounded())
            DispatchQueue.main.async { [weak self] in self?.report?(measured) }
        }
    }
}
