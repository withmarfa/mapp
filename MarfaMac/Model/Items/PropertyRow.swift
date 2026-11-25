import Foundation
import Marfa

/// One row of an item's head, or one pin above it: the label and a value drawn by the kind of field it came from. A row
/// the item can take an edit for (`editable`) opens its editor under the value, as the status and the parent keep their
/// menus. `PageHead` decides which rows show.
nonisolated struct PropertyRow: Identifiable, Hashable, Sendable {
    /// An item a row links to.
    struct Target: Hashable, Sendable {
        let title: String
        let item: ItemID
        /// The icon of the item's type, an Iconify ID, which the page draws before the title.
        var icon: String?
        var kind: Kind = .link

        /// How the page draws the item: as its type does (a type mark and tint), or as a person (initials, then the name).
        enum Kind: String, Hashable, Sendable { case link, person }
    }

    enum Value: Hashable, Sendable {
        /// The status pill, drawn by the page from the head's status menu. A status not set is `empty`.
        case status
        /// The parent's pill, drawn the same way. A pinned parent is `items`, a link that only opens it.
        case parent
        case items([Target])
        /// The entries of a list of people, each by the name it goes by (`ListShape.personName`), drawn as the person chip.
        case people([String])
        /// A choice, or a list of words a field holds, such as labels: each drawn with a dot of its own color.
        case options([String])
        /// The item's own tags, each drawn after a `#`.
        case tags([String])
        /// A date or datetime as a person reads it.
        case date(String)
        /// An event's time, and after it in grey how far off it is, or All Day.
        case when(String, note: String)
        case url(String)
        case email(String)
        /// A number to call.
        case phone(String)
        case boolean(Bool)
        /// Text, a choice's label or a number.
        case text(String)
        /// A value the item does not have, drawn as the word Empty. The symbol is the one a value of the field's kind has.
        case empty(symbol: String)

        /// The SF Symbol that stands for the kind of value beside its label.
        var symbol: String {
            switch self {
            case .status: "circle.dotted"
            case .parent: "square.stack"
            case .items: "link"
            case .people: "person.2"
            case .options: "list.bullet"
            case .tags: "tag"
            case .date: "calendar"
            case .when: "clock"
            case .url: "globe"
            case .email: "envelope"
            case .phone: "phone"
            case .boolean: "checkmark.square"
            case .text: "text.alignleft"
            case .empty(let symbol): symbol
            }
        }

        /// Every symbol a row can show, for a page that draws them as images.
        static let symbols = ["circle.dotted", "square.stack", "link", "tag", "calendar", "globe", "envelope", "phone", "checkmark.square", "text.alignleft", "list.bullet", "person.2", "clock", ItemLocation.symbol]
    }

    let id: String
    let label: String
    var value: Value
    /// The number to call the main entry of a list holds, where its list can hold one (`ListShape.numberToCall`).
    var numberToCall: String?
    /// How many values of a list a pin left out, for the "+N more" after the first value (`PageHead.moreText`). Always
    /// 0 in the rows.
    var more = 0
    /// The words of the whole value, where the row shows less of it: a list a pin cut, or an event's time with its
    /// zone. Nil for any row that shows its whole value.
    var help: String?
    /// Whether the value opens an editor under it, or for a yes or no flips: any value that can be edited, on an item
    /// that can take the edit. The app says so; the page never decides it.
    var editable = false
    /// The color of each value of an `options` row that takes its color from the field and not from its words: a task's
    /// priority, by rank (`OptionTone.tone(of:in:isPriority:)`). Empty for any other row, whose values take the color
    /// of their words (`OptionTone.tone(for:)`).
    var optionTones: [TypeTone] = []
    /// The symbol beside the label where it is not the one the value's kind gives: a Location's pin, whose value is text.
    var symbol: String?
    /// Text that may run to a second line before it is cut.
    var long = false
    /// Shown only once Show More is open (`PageHead`).
    var folded = false
    /// Hidden on the type's pages, so drawn grey under Show More.
    var muted = false
    /// Why a link the item may hold takes no change, in the person's words, which the row's help tag says. Nil for every
    /// row that is not a read-only link.
    var lock: String?
    /// The heading a row sits under in Show More, worded by the app: the values no field describes (`otherHeading`).
    /// Such a row is read only and has no place in the type's order.
    var section: String?

    /// The symbol drawn beside the label.
    var symbolName: String { symbol ?? value.symbol }

    /// The words of the row's value, for its help and its accessibility label: every value of a list, even where a pin
    /// shows only the first.
    var wholeValue: String {
        if let help { return help }
        switch value {
        case .status, .parent, .empty: return ""
        case .items(let targets): return targets.map(\.title).joined(separator: ", ")
        case .people(let words), .options(let words), .tags(let words): return words.joined(separator: ", ")
        case .when(let time, let note): return "\(time), \(note)"
        case .date(let text), .text(let text), .url(let text), .email(let text), .phone(let text): return text
        case .boolean(let flag): return flag ? String(localized: "Yes") : String(localized: "No")
        }
    }

    /// Whether the row is a value the item does not have.
    var isEmpty: Bool {
        if case .empty = value { true } else { false }
    }

    /// A text value too long to read in a list's row or a table's cell, which shows nothing for it.
    static let longestText = 120

    /// The heading of the rows for values no field describes.
    static var otherHeading: String { String(localized: "Other") }

    /// The prefix of such a row's identifier, which no field's key or edge's name starts with.
    static let otherPrefix = "other:"

    /// Every row the item could show, whatever the person chose, in the order a person reads them: the type's fields as
    /// the catalogue orders them, with the parent after the status and the choices and dates that follow it (or first,
    /// where the type has no status), and one Location for the latitude, the longitude and a name for the place; then
    /// every link the item's type may hold (`links`), the ones it has first; then its tags; then the values no field
    /// describes, read only, under their own heading. A field, a link or the tags with no value is a row too, read as Empty, which opens its editor where the
    /// item can take the edit. The keys in `hidden` are what the page shows another way, such as the title and the
    /// text. With `showsCoordinates`, the latitude and longitude are rows of their own beside the Location that stands
    /// for them.
    static func candidates(
        of item: Item, type: ItemTypeInfo?, hidden: Set<String>, links: [RelationField], format: DateFormat, tags: [String],
        showsCoordinates: Bool = false, isPriority: (ItemTypeInfo.Field) -> Bool = { _ in false }, icon: (ItemID) -> String?,
        isPerson: (ItemID) -> Bool, label: (String) -> String? = { _ in nil }
    ) -> [PropertyRow] {
        let parentField = PagePlacement.parent
        var fields: [PropertyRow] = []
        let parentRow = links.first { $0.field == parentField }.map { edgeRow($0, icon: icon, isPerson: isPerson) }
        let status = type?.statusField
        let location = ItemLocation.of(type)
        let owned = location?.ownedKeys(showingCoordinates: showsCoordinates) ?? []
        var locationDrawn = false
        for field in type?.fields ?? [] where !hidden.contains(field.key) {
            if let location, location.keys.contains(field.key) {
                // One row stands for the point and its name, where the first of them is.
                if !locationDrawn { fields.append(location.row(of: item)) }
                locationDrawn = true
                if owned.contains(field.key) { continue }
            }
            let edits = item.allows(.fields) && isEdited(field)
            if field.key == status?.key {
                let set = item.value(of: field.key)?.string.map { !$0.isEmpty } ?? false
                fields.append(set
                    ? PropertyRow(id: field.key, label: field.label, value: .status)
                    : PropertyRow(id: field.key, label: field.label, value: .empty(symbol: Value.status.symbol), editable: edits && field.isPicked))
            } else if let value = value(of: field, in: item, format: format, long: true) {
                var row = PropertyRow(
                    id: field.key, label: field.label, value: value, numberToCall: numberToCall(of: field, in: item), editable: edits,
                    optionTones: optionTones(of: field, in: item, isPriority: isPriority(field)))
                if case .text(let text) = value { row.long = text.count > longestText || text.contains(where: \.isNewline) }
                // A number to call opens the phone, as an address opens its page.
                if let number = row.numberToCall { row.value = .phone(number) }
                fields.append(row)
            } else if !InspectorFields.hasValue(item.value(of: field.key)) {
                fields.append(PropertyRow(id: field.key, label: field.label, value: .empty(symbol: symbol(of: field)), editable: edits))
            }
        }
        if let parentRow { fields.insert(parentRow, at: parentPlace(among: fields, of: type)) }
        var rows = fields
        for link in links where link.field != parentField { rows.append(edgeRow(link, icon: icon, isPerson: isPerson)) }
        rows.append(tags.isEmpty
            ? PropertyRow(id: PagePlacement.tags, label: String(localized: "Tags"), value: .empty(symbol: "tag"), editable: item.allows(.tags))
            : PropertyRow(id: PagePlacement.tags, label: String(localized: "Tags"), value: .tags(tags), editable: item.allows(.tags)))
        return rows + otherRows(of: item, type: type, hidden: hidden, links: links, format: format, label: label)
    }

    /// Where the parent goes among the rows of the type's fields: after the status and the choices and dates that follow
    /// it, which say how the item stands, or first where no row is the status.
    private static func parentPlace(among rows: [PropertyRow], of type: ItemTypeInfo?) -> Int {
        guard let status = type?.statusField?.key, var place = rows.firstIndex(where: { $0.id == status }) else { return 0 }
        let following = Set((type?.fields ?? []).filter { field in
            switch field.kind {
            case .choice, .date: true
            default: false
            }
        }.map(\.key))
        repeat { place += 1 } while place < rows.count && following.contains(rows[place].id)
        return place
    }

    /// The row of one link the item's type may hold: the items it reaches, or Empty. It opens its editor where the item
    /// takes the change, and otherwise says why not.
    static func edgeRow(_ link: RelationField, icon: (ItemID) -> String?, isPerson: (ItemID) -> Bool) -> PropertyRow {
        var row: PropertyRow
        let targets = link.targets.compactMap { target -> Target? in
            guard target.isOpenable, !target.isDeleted, let id = target.itemID else { return nil }
            return Target(title: target.title, item: id, icon: icon(id), kind: isPerson(id) ? .person : .link)
        }
        if link.field == PagePlacement.parent {
            // The parent is the head's own pill where there is one.
            row = PropertyRow(id: link.field, label: link.label, value: link.targets.isEmpty ? .empty(symbol: Value.parent.symbol) : .parent)
        } else {
            row = PropertyRow(id: link.field, label: link.label, value: targets.isEmpty ? .empty(symbol: Value.items([]).symbol) : .items(targets))
        }
        // A collection has its own mark, the one its places wear.
        if link.field == MarfaMapping.collectionEdge { row.symbol = SidebarPlace.collections.symbol }
        switch link.editability {
        case .editable: row.editable = true
        case .readOnly(let reason): row.lock = reason
        }
        return row
    }

    /// The values the item holds that no field of its type describes and no link names, in the order it holds them, as
    /// rows to read.
    private static func otherRows(
        of item: Item, type: ItemTypeInfo?, hidden: Set<String>, links: [RelationField], format: DateFormat, label: (String) -> String?
    ) -> [PropertyRow] {
        let known = InspectorFields.accountedFor(type: type, hidden: hidden).union(links.map(\.field))
        return item.properties.compactMap { property in
            guard !known.contains(property.key), InspectorFields.hasValue(property.value) else { return nil }
            let value = ItemValueText.value(of: property.value, format: format)
            var row = PropertyRow(
                id: otherPrefix + property.key, label: ItemValueText.name(of: property.key, label: label(property.key)), value: value, section: otherHeading)
            if case .text(let text) = value { row.long = text.count > longestText || text.contains(where: \.isNewline) }
            return row
        }
    }

    /// Whether the page edits the field's value: in a panel, or for a yes or no with a click.
    private static func isEdited(_ field: ItemTypeInfo.Field) -> Bool {
        field.kind == .boolean || ValueEditKind(field: field) != nil
    }

    /// The symbol a value of the field's kind has beside its name, as `Value.symbol` gives it to the value itself.
    private static func symbol(of field: ItemTypeInfo.Field) -> String {
        switch field.kind {
        case .date: Value.date("").symbol
        case .boolean: Value.boolean(false).symbol
        case .list(let shape) where shape.holdsPeople: Value.people([]).symbol
        case .status: Value.status.symbol
        case .choice, .words, .list: Value.options([]).symbol
        case .text where field.format == .url: Value.url("").symbol
        case .text where field.format == .email: Value.email("").symbol
        default: Value.text("").symbol
        }
    }

    /// The number to call a list field's main entry holds, or nil.
    static func numberToCall(of field: ItemTypeInfo.Field, in item: Item) -> String? {
        guard case .list(let shape) = field.kind, let main = ListEntries.main(of: item.value(of: field.key)) else { return nil }
        return shape.numberToCall(in: main)
    }

    /// The color of each option `field` holds in `item`, for a field that colors its options by rank; empty for any other.
    static func optionTones(of field: ItemTypeInfo.Field, in item: Item, isPriority: Bool) -> [TypeTone] {
        guard isPriority, let stored = item.value(of: field.key) else { return [] }
        switch (field.kind, stored) {
        case (.choice, .string(let text)): return [OptionTone.tone(of: text, in: field, isPriority: true)]
        default: return []
        }
    }

    /// The value a field's row draws, or nil where the field has none or holds something a row does not show. Text
    /// longer than `longestText` or of more than one line is left out of a list's row and a table's cell, and shown by a
    /// page's head (`long`), which cuts it after two lines.
    static func value(of field: ItemTypeInfo.Field, in item: Item, format: DateFormat, long: Bool = false) -> Value? {
        guard let stored = item.value(of: field.key), InspectorFields.hasValue(stored) else { return nil }
        switch (field.kind, stored) {
        case (.list(let shape), .array(let entries)):
            if shape.holdsPeople {
                let names = entries.compactMap { ListEntries.object($0).flatMap(shape.personName(of:)) }
                return names.isEmpty ? nil : .people(names)
            }
            // Only the main entry shows on the page; Show More lists them all.
            guard let main = entries.first.flatMap(ListEntries.object) else { return nil }
            return shape.rowValue(of: main)
        case (.boolean, .bool(let flag)): return .boolean(flag)
        case (.number, .number(let number)): return .text(number.formatted())
        case (.number, .double(let number)): return .text(number.readable)
        case (.date, .string(let text)): return .date(ItemDate.parse(text)?.text(format: format) ?? text)
        case (.choice, .string(let text)): return .options([ItemTypeInfo.Field.label(ofOption: text)])
        case (.text, .string(let text)):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if field.format == .url { return .url(text) }
            if field.format == .email { return .email(text) }
            guard long || (!text.contains(where: \.isNewline) && text.count <= longestText) else { return nil }
            return .text(text)
        case (_, .array(let values)):
            let words = values.compactMap(\.string).filter { !$0.isEmpty }
            return words.count == values.count && !words.isEmpty ? .options(words) : nil
        default: return nil
        }
    }
}
