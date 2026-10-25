import AppKit
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
    @State private var isHovering = false

    var body: some View {
        content
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .onHover { isHovering = $0 }
    }

    @ViewBuilder private var content: some View {
        switch column.content {
        case .title: title
        case .type: Label { Text(row.typeLabel) } icon: { Image(systemName: row.typeSymbol) }
            .labelStyle(ItemTableLabelStyle())
            .foregroundStyle(.secondary)
        case .parent: link(row.parent)
        case .collection: link(row.collection)
        case .created: date(row.item.created, isDue: false)
        case .edited: date(row.item.modified, isDue: false)
        case .duration(let start, let end):
            if let seconds = ItemTableValue.duration(row, start: start, end: end) {
                Text(Duration.seconds(seconds), format: .units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        // A mixed table's column holds one type's field; each cell offers its own type's, whose values may differ.
        case .field(let field): value(of: library.catalogue.itemTypes[row.item.type]?.fields.first { $0.key == field.key } ?? field)
        }
    }

    // MARK: The name

    private var title: some View {
        HStack(spacing: 8) {
            Image(systemName: row.typeSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(row.item.title.isEmpty ? String(localized: "Untitled") : row.item.title)
                .fontWeight(.medium)
                .foregroundStyle(row.item.title.isEmpty ? .secondary : .primary)
                .truncationMode(.tail)
            if row.item.isFavorite {
                Image(systemName: "star.fill")
                    .imageScale(.small)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
            Spacer(minLength: 8)
            // Notion's Open: a click opens the page, where selecting the row would only show it in Details.
            Button {
                browser.selection = [row.id]
                browser.openCollectionSelection()
            } label: {
                Label("Open", systemImage: "arrow.up.right")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.background, in: .capsule)
                    .overlay { Capsule().strokeBorder(.separator) }
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .accessibilityHidden(!isHovering)
        }
    }

    // MARK: Values

    @ViewBuilder private func value(of field: ItemTypeInfo.Field) -> some View {
        let current = ItemTableValue.string(row, key: field.key)
        let declares = library.catalogue.itemTypes[row.item.type]?.declares(field.key) ?? false
        let editable = declares && row.item.isEditable
        switch column.style {
        case .status, .priority, .choice:
            picked(field, current: current, editable: editable)
        case .person where field.isPicked:
            picked(field, current: current, editable: editable)
        case .boolean:
            let isOn: Bool = if case .bool(let flag)? = row.item.value(of: field.key) { flag } else { false }
            if declares {
                Toggle(field.displayLabel, isOn: Binding { isOn } set: { set(field, .bool($0)) })
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!editable)
            }
        case .date:
            if let current {
                if let day = ItemTableValue.date(current) {
                    date(day, isDue: field.key == "due_at")
                } else {
                    Text(current).foregroundStyle(.secondary)
                }
            }
        case .number:
            if let current { Text(current).monospacedDigit() }
        case .person:
            if let current { ItemTableCategory(column: column, value: current, title: column.label(ofCategory: current, in: [row])) }
        case .longText:
            if let current { Text(current).foregroundStyle(.secondary).truncationMode(.tail) }
        default:
            if let current { Text(current).truncationMode(.tail) }
        }
    }

    /// A value from a fixed set: a menu of the others where it can be changed, the value alone where it cannot.
    @ViewBuilder private func picked(_ field: ItemTypeInfo.Field, current: String?, editable: Bool) -> some View {
        if editable {
            picker(field, current: current)
        } else if let current {
            ItemTableCategory(column: column, value: current, title: column.label(ofCategory: current, in: [row]))
        }
    }

    /// A value picked from the field's options, as the cell shows it, opening a menu of the others.
    private func picker(_ field: ItemTypeInfo.Field, current: String?) -> some View {
        Menu {
            Picker(field.displayLabel, selection: Binding { current ?? "" } set: { set(field, $0.isEmpty ? nil : .string($0)) }) {
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
                    ItemTableCategory(column: column, value: current, title: ItemTypeInfo.Field.label(ofOption: current))
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
        .accessibilityLabel(Text(field.displayLabel))
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
                Label { Text(link.title).underline(isHovering) } icon: { Image(systemName: link.symbol) }
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
            && !(row.item.value(of: "status")?.string.map { StatusTone($0).isFinished } ?? false)
        return Text(ItemTableDate.label(for: date, now: now))
            .foregroundStyle(isLate ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .monospacedDigit()
    }
}

/// A category's mark and name, the same in a cell, a menu and a group's header: a status's ring, a priority's bars,
/// a person's initial, or a link's symbol.
struct ItemTableCategory: View {
    let column: ItemTableColumn
    let value: String?
    let title: String

    var body: some View {
        switch column.style {
        case .status:
            Label {
                Text(title)
            } icon: {
                StatusMark(mark: PageHeader.Mark(status: value), size: 12)
            }
            .labelStyle(ItemTableLabelStyle())
        case .priority:
            Label {
                Text(title).foregroundStyle(value == nil ? .secondary : .primary)
            } icon: {
                PriorityBars(rank: value.map(column.rank(of:)), count: column.field?.options.count ?? 4)
            }
            .labelStyle(ItemTableLabelStyle())
        case .person:
            Label {
                Text(title)
            } icon: {
                if let value { Avatar(name: value) } else { Image(systemName: "person.crop.circle.dashed").foregroundStyle(.tertiary) }
            }
            .labelStyle(ItemTableLabelStyle())
        case .link where column.content == .collection:
            Label { Text(title) } icon: { Image(systemName: value == nil ? "folder.badge.questionmark" : "folder").foregroundStyle(.secondary) }
                .labelStyle(ItemTableLabelStyle())
        default:
            Text(title)
        }
    }
}

/// A category as a menu item: a menu shows images but not views, so a status's ring is drawn into one.
struct ItemTableMenuLabel: View {
    let column: ItemTableColumn
    let value: String?
    let title: String

    var body: some View {
        if column.style == .status {
            Label { Text(title) } icon: { Self.ring(for: value) }
        } else {
            ItemTableCategory(column: column, value: value, title: title)
        }
    }

    private static func ring(for status: String?) -> Image {
        let renderer = ImageRenderer(content: StatusMark(mark: PageHeader.Mark(status: status), size: 12).padding(1))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage.map { Image(nsImage: $0) } ?? Image(systemName: "circle")
    }
}

/// A priority as signal bars: one filled for the lowest, all of them for the highest, which is also red.
private struct PriorityBars: View {
    let rank: Int?
    let count: Int

    var body: some View {
        let level = rank.map { Double($0 + 1) / Double(max(count, 1)) } ?? 0
        Image(systemName: "cellularbars", variableValue: level)
            .foregroundStyle(level >= 1 ? AnyShapeStyle(.red) : level >= 0.75 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .accessibilityHidden(true)
    }
}

/// A person's initial in a circle, its color steady for the name.
private struct Avatar: View {
    let name: String
    private static let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .green, .indigo, .brown]

    var body: some View {
        let color = Self.colors[Int(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ $1.value) % 9973 }) % Self.colors.count]
        Text(name.prefix(1).uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(color.gradient, in: .circle)
            .accessibilityHidden(true)
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

/// How the table writes a day.
nonisolated enum ItemTableDate {
    static func label(for date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return String(localized: "Today")
        case -1: return String(localized: "Yesterday")
        case 1: return String(localized: "Tomorrow")
        case -6...(-2), 2...6:
            return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
        default:
            let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
            if !sameYear { style = style.year() }
            return date.formatted(style)
        }
    }
}
