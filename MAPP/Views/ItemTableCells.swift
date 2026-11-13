import AppKit
import Marfa
import MarfaIcons
import SwiftUI

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
    let order: NoteOrder
    let dateFormat: DateFormat
    /// Which row the pointer is on, shared by the row's cells, so the name's cell can answer to it from any of them.
    let hover: ItemTableHover
    @State private var isHovering = false

    var body: some View {
        content
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
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

    private func setHovering(_ inside: Bool) {
        guard inside != isHovering else { return }
        isHovering = inside
        if inside { hover.enter(row.id) } else { hover.exit(row.id) }
    }

    @ViewBuilder private var content: some View {
        switch column.content {
        case .title: title
        case .type: PageChip(text: row.typeLabel, kind: .type(icon: row.typeIcon), size: .row)
        case .parent: link(row.parent)
        case .created: date(row.item.created, isDue: false)
        case .edited: date(row.item.modified, isDue: false)
        case .occurred: date(row.item.occurred ?? row.item.created, isDue: false)
        case .tags: tags
        case .duration(let start, let end):
            if let seconds = ItemTableValue.duration(row, start: start, end: end) {
                Text(Duration.seconds(seconds), format: .units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        // A mixed table's column holds the words of every type; each cell offers its own row's type's.
        case .field(let field): value(of: column.field(for: row, catalogue: library.catalogue) ?? field)
        }
    }

    // MARK: The name

    private var title: some View {
        HStack(spacing: 8) {
            TypeGlyph(id: row.typeIcon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(row.item.displayTitle)
                .fontWeight(.medium)
                .foregroundStyle(row.item.isUntitled ? .secondary : .primary)
                .truncationMode(.tail)
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
            browser.selection = [row.id]
            browser.openCollectionSelection()
        } label: {
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.thinMaterial, in: .rect(cornerRadius: 6, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator) }
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
        let editable = declares && row.item.isEditable
        switch column.style {
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
                if let day = ItemDate.parse(current)?.date {
                    date(day, isDue: library.catalogue.isDueDate(field, of: row.item.type))
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
            PageChip(text: label, kind: .status(StatusSymbol(group: field.statusGroup(of: value)), chevron: false), size: .row)
        } else {
            PageChip(
                text: label,
                kind: .option(OptionTone.tone(of: value, in: field, isPriority: column.style == .priority)), size: .row)
        }
    }

    /// A value from a fixed set: a menu of the others where it can be changed, the value alone where it cannot.
    @ViewBuilder private func picked(_ field: ItemTypeInfo.Field, current: String?, editable: Bool) -> some View {
        if editable {
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
            HStack(spacing: 4) {
                if let current {
                    chip(current, field: field)
                } else if isHovering {
                    Text("Empty").foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 5, style: .continuous))
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .padding(.horizontal, -5)
        .accessibilityLabel(Text(field.label))
        .accessibilityValue(Text(current.map(ItemTypeInfo.Field.label(ofOption:)) ?? String(localized: "Not Set")))
    }

    private func set(_ field: ItemTypeInfo.Field, _ value: PropertyValue?) {
        library.setItemProperty(row.id, key: field.key, value: value, undoManager: undoManager)
    }

    /// Where the item is filed, as a link that shows that item.
    @ViewBuilder private func link(_ link: ItemTableRow.Link?) -> some View {
        if let link {
            Button {
                if let item = library.item(link.id) { browser.reveal(item, in: library, order: order) }
            } label: {
                Label { Text(link.title).underline(isHovering) } icon: { TypeGlyph(id: link.icon) }
                    .labelStyle(ItemTableLabelStyle())
            }
            .buttonStyle(.plain)
            .help(Text("Show \(link.title)"))
        }
    }

    /// A day as people say it: Today, Yesterday, a weekday this week, then the date. A due date already past, on
    /// work not finished, is red.
    private func date(_ date: Date, isDue: Bool) -> some View {
        let now = library.now()
        let isLate = isDue && date < Calendar.current.startOfDay(for: now)
            && library.catalogue.statusGroup(of: row.item)?.isFinished != true
        return Text(DateDisplay.text(of: date, hasTime: false, place: .table, format: dateFormat, now: now))
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
                StatusMark(group: statusGroup, size: 12)
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
        let renderer = ImageRenderer(content: StatusMark(group: group, size: 12).padding(1))
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
