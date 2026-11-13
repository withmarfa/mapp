import Foundation
import Marfa

/// One line of the facts beside a version: a name and what it says.
nonisolated struct VersionFactRow: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let value: String
    /// The symbol of a pin's key, as the item's page draws it. The sidebar's rows have none.
    var symbol: String?
}

/// What the right sidebar says of the version chosen: who wrote it and when, what it changed from the version before,
/// and what has changed since. Pure, so the sidebar only draws it.
nonisolated struct VersionFacts: Equatable, Sendable {
    var writtenBy: String?
    var version: Int
    /// The version the item holds now, so the person reads "4 of 10".
    var latest: Int
    var saved: Date?
    var savedIsApproximate: Bool
    /// Whether there is an earlier version to compare with.
    var hasEarlier: Bool
    var changedHere: [VersionFactRow]
    var changedSince: [VersionFactRow]
    var isCurrent: Bool

    static func make(
        for entry: VersionEntry, after older: VersionEntry?, current: VersionEntry, in catalogue: Catalogue,
        dateFormat: DateFormat, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> VersionFacts {
        func value(_ value: PropertyValue?, _ field: ItemTypeInfo.Field?) -> String {
            Self.text(of: value, field: field, format: dateFormat, now: now, calendar: calendar, locale: locale)
        }
        var here: [VersionFactRow] = []
        if let older {
            let delta = VersionDelta.between(older.content, entry.content, in: catalogue)
            if delta.typeChanged {
                here.append(VersionFactRow(id: "#type", label: String(localized: "Type"), value: Self.typeName(entry.content.type, in: catalogue)))
            }
            if delta.titleChanged {
                here.append(VersionFactRow(id: "#title", label: String(localized: "Title"), value: String(localized: "Changed")))
            }
            if delta.textChanged, let before = older.content.text, let after = entry.content.text {
                let counts = WordDiff.counts(WordDiff.pieces(from: before, to: after))
                here.append(VersionFactRow(id: "#text", label: String(localized: "Text"), value: Self.describe(additions: counts.added, removals: counts.removed)))
            }
            here += delta.fields.map { change in
                VersionFactRow(id: change.key, label: change.label, value: change.to == nil ? String(localized: "Cleared") : value(change.to, change.field))
            }
        }
        var since: [VersionFactRow] = []
        if !entry.isCurrent {
            let delta = VersionDelta.between(entry.content, current.content, in: catalogue)
            if delta.typeChanged {
                since.append(VersionFactRow(id: "#type", label: String(localized: "Type"), value: Self.typeName(current.content.type, in: catalogue)))
            }
            if delta.titleChanged {
                since.append(VersionFactRow(id: "#title", label: String(localized: "Title"), value: String(localized: "Changed")))
            }
            if delta.textChanged, let before = entry.content.text, let after = current.content.text {
                let changes = WordDiff.changes(WordDiff.pieces(from: before, to: after))
                since.append(VersionFactRow(
                    id: "#text", label: String(localized: "Text"),
                    value: changes == 0 ? String(localized: "Changed") : AttributedString(localized: "^[\(changes) change](inflect: true)").text))
            }
            since += delta.fields.map { change in
                VersionFactRow(id: change.key, label: change.label, value: change.to == nil ? String(localized: "Cleared") : value(change.to, change.field))
            }
        }
        return VersionFacts(
            writtenBy: entry.writer?.displayName, version: entry.version, latest: current.version, saved: entry.written,
            savedIsApproximate: entry.writtenIsApproximate, hasEarlier: older != nil, changedHere: here, changedSince: since,
            isCurrent: entry.isCurrent)
    }

    static func describe(additions: Int, removals: Int) -> String {
        switch (additions, removals) {
        case (0, 0): return String(localized: "Changed")
        case (_, 0): return AttributedString(localized: "^[\(additions) addition](inflect: true)").text
        case (0, _): return AttributedString(localized: "^[\(removals) removal](inflect: true)").text
        default:
            let added = AttributedString(localized: "^[\(additions) addition](inflect: true)").text
            let removed = AttributedString(localized: "^[\(removals) removal](inflect: true)").text
            return String(localized: "\(added), \(removed)")
        }
    }

    static func typeName(_ type: TypeID, in catalogue: Catalogue) -> String {
        catalogue.itemTypes[type]?.label ?? type.rawValue
    }

    /// A field's value as a person reads it: a picked word as the app writes it, a date in the person's format.
    static func text(
        of value: PropertyValue?, field: ItemTypeInfo.Field?, format: DateFormat, now: Date, calendar: Calendar, locale: Locale
    ) -> String {
        guard let value, value != .null else { return String(localized: "None") }
        if let field {
            if field.isPicked, let word = value.string { return ItemTypeInfo.Field.label(ofOption: word) }
            if case .date = field.kind, let text = value.string, let date = ItemDate.parse(text, calendar: calendar) {
                return date.text(format: format, now: now, locale: locale, calendar: calendar)
            }
        }
        return value.displayText
    }
}

nonisolated extension ItemSnapshot.Writer {
    /// The sign-in's own name, else the kind of sign-in it was.
    var displayName: String {
        guard name.isEmpty else { return name }
        return switch kind {
        case .browser: String(localized: "Browser")
        case .app: String(localized: "App")
        case .key: String(localized: "Key")
        case .local: String(localized: "This device")
        }
    }
}

// MARK: Pins

nonisolated extension VersionContent {
    /// The properties the page would pin for this version, as the type's pins name them, so a version reads like the
    /// page does. Only what a version holds is shown: its type, and the fields it has. The item's tags, parent, location and
    /// last edit are not in a version, so those pins are left out rather than shown from the item as it is now.
    func pins(
        saved: Date?, placement: PagePlacement, in catalogue: Catalogue, format: DateFormat, now: Date = .now,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> [VersionFactRow] {
        let info = catalogue.itemTypes[type]
        var rows: [VersionFactRow] = []
        for pin in placement.pins {
            switch pin {
            case PagePlacement.type:
                rows.append(VersionFactRow(id: pin, label: String(localized: "Type"), value: info?.label ?? type.rawValue, symbol: "square.grid.2x2"))
            case PagePlacement.updated:
                if let saved {
                    rows.append(VersionFactRow(
                        id: pin, label: String(localized: "Updated"),
                        value: ItemDate.text(of: saved, hasTime: false, format: format, now: now, locale: locale, calendar: calendar),
                        symbol: "calendar"))
                }
            case PagePlacement.source, PagePlacement.tags, PagePlacement.linkedFrom, PagePlacement.parent, PagePlacement.location:
                continue
            default:
                guard let field = info?.fields.first(where: { $0.key == pin }), let value = fields[pin], value != .null else { continue }
                let text = VersionFacts.text(of: value, field: field, format: format, now: now, calendar: calendar, locale: locale)
                if !text.isEmpty { rows.append(VersionFactRow(id: pin, label: field.label, value: text, symbol: PageLayout.symbol(of: field))) }
            }
        }
        return rows
    }
}
