import Foundation

/// An earlier version of an item as the library kept it: the item as it stood at `version`, before the write that
/// replaced it. The version the item holds now has no snapshot.
nonisolated struct ItemSnapshot: Identifiable, Hashable, Sendable {
    nonisolated struct Writer: Hashable, Sendable {
        enum Kind: Hashable, Sendable { case browser, app, key, local }
        let kind: Kind
        /// What the library calls the sign-in that wrote it, such as a key's label or an app's name.
        let name: String
    }

    let id: String
    let version: Int
    /// The type the item had at this version, which may not be the type it has now.
    let type: TypeID
    let properties: [String: PropertyValue]
    /// When this version was written; nil where the library did not say or the time could not be read.
    let written: Date?
    /// Nil where the library does not know who wrote it.
    let writer: Writer?
}

/// One page of an item's snapshots, oldest first. A page can be short or empty while `next` still leads on.
nonisolated struct ItemHistoryPage: Hashable, Sendable {
    var snapshots: [ItemSnapshot]
    /// Where the next page starts; nil on the last page.
    var next: String?
}

/// Why an item's history could not be read, in terms the sheet can word for a person.
nonisolated enum ItemHistoryFailure: Error, Hashable, Sendable {
    /// The server could not be reached. The package reports a refused plain-http address the same way as a network
    /// that is down, so the wording does not say which.
    case unreachable
    /// The key MAPP uses may not read this item's history.
    case notPermitted
    /// The server holds no readable history for the item: it is deleted, of a type the key cannot read, or not sent
    /// to the server yet.
    case unavailable
    /// The server did not accept the key.
    case keyRefused
    /// This library keeps no history to read.
    case unsupported
    case failed(String)

    var message: String {
        switch self {
        case .unreachable:
            String(localized: "MAPP can’t reach the server. Version history comes from the server. If its address starts with http://, macOS may be refusing it. Your notes and changes aren’t affected.")
        case .notPermitted:
            String(localized: "The key MAPP uses isn’t allowed to read this item’s history. Ask whoever runs the server to allow it.")
        case .unavailable:
            String(localized: "The server has no history to show for this item. It may be new and not sent yet, deleted, or of a kind your key can’t read.")
        case .keyRefused:
            String(localized: "The server didn’t accept MAPP’s key. Choose a new key in Settings.")
        case .unsupported:
            String(localized: "This library doesn’t keep version history.")
        case .failed(let message):
            message
        }
    }
}

/// Where an item's snapshots come from. Reading them is a request to the server, which the working copy does not
/// keep, so it can fail while the rest of the library works.
nonisolated protocol ItemHistorySource: Sendable {
    /// A page of at most `limit` snapshots after `cursor` (nil for the first), oldest first.
    func page(of id: ItemID, after cursor: String?, limit: Int) async throws(ItemHistoryFailure) -> ItemHistoryPage
}

nonisolated extension ItemSnapshot {
    /// The text this version held, read from the field its type keeps text in. Nil for a type that holds none or
    /// that the catalogue does not know. A type with a text field and no value held empty text.
    func text(in catalogue: Catalogue) -> String? {
        guard let key = catalogue.itemTypes[type]?.bodyKey else { return nil }
        switch properties[key] {
        case nil, .null?: return ""
        case .string(let text)?: return text
        default: return nil
        }
    }

    /// The title this version held, where its type keeps one as a property.
    func title(in catalogue: Catalogue) -> String? {
        guard let key = catalogue.itemTypes[type]?.titleKey else { return nil }
        return properties[key]?.string
    }

    /// The other fields of this version, by label, for reading: not the title and the text, which are shown
    /// beside the current ones.
    func fields(in catalogue: Catalogue) -> [(label: String, value: String)] {
        let info = catalogue.itemTypes[type]
        let hidden = Set([info?.bodyKey, info?.titleKey].compactMap { $0 })
        return properties.filter { !hidden.contains($0.key) && $0.value != .null }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { key, value in
                (info?.fields.first { $0.key == key }?.displayLabel ?? key, value.displayText)
            }
    }
}

nonisolated extension PropertyValue {
    /// The value as a line of text for reading.
    var displayText: String {
        switch self {
        case .null: ""
        case .bool(let value): value ? String(localized: "Yes") : String(localized: "No")
        case .number(let value): value.formatted(.number)
        case .string(let value): value
        case .array(let values): values.map(\.displayText).joined(separator: ", ")
        case .object(let values):
            values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.displayText)" }.joined(separator: ", ")
        }
    }
}

/// How much of a version's text the sheet lays out. A long note is cut here, for the person to read the start of it
/// and to see that it was cut, rather than the sheet laying out a text of any length.
nonisolated struct TextExcerpt: Hashable, Sendable {
    static let limit = 20_000

    let text: String
    /// How many characters were left out.
    let omitted: Int

    init(_ full: String, limit: Int = Self.limit) {
        let shown = full.prefix(limit)
        text = String(shown)
        omitted = full.count - shown.count
    }
}

// MARK: Restoring

/// What a restore changes on the item as it stands: the text and the title it would be given, each nil where it
/// stays as it is.
nonisolated struct RestorePlan: Hashable, Sendable {
    var text: String?
    var title: String?

    var isEmpty: Bool { text == nil && title == nil }
}

nonisolated enum RestoreCheck: Hashable, Sendable {
    case ready(RestorePlan)
    /// The item already holds this version's text and title.
    case unchanged
    /// Why this version can't be restored, in the person's words.
    case unavailable(String)
}

extension ItemLibrary {
    /// What restoring `snapshot` over item `id` would change, judged on the item as the library holds it now.
    ///
    /// Only the text and the title are restored: they are what a note is, and they map between types whenever both
    /// types keep them. The item's other fields stay as they are, so a restore never brings back a value another
    /// device has since changed on purpose, and the version's own fields are shown for reading.
    func restoreCheck(of snapshot: ItemSnapshot, for id: ItemID) -> RestoreCheck {
        guard let item = item(id) else {
            return .unavailable(String(localized: "This item is no longer in the library."))
        }
        if item.state == .trashed {
            return .unavailable(String(localized: "This item is in Recently Deleted. Recover it to restore a version."))
        }
        if item.isFile {
            return .unavailable(String(localized: "A file’s versions can be read here, but not restored."))
        }
        guard item.isWritable else {
            return .unavailable(String(localized: "This item can’t be changed right now."))
        }
        let current = catalogue.itemTypes[item.type]
        let text = snapshot.text(in: catalogue)
        let canWriteText = current?.bodyKey != nil && body(of: id) != nil
        let title = snapshot.title(in: catalogue)
        var plan = RestorePlan()
        var comparable = false
        if let text, canWriteText {
            comparable = true
            if text != body(of: id)?.text { plan.text = text }
        }
        if let title, !NoteName.trimmed(title).isEmpty, case .property = item.titleRule {
            comparable = true
            if title != item.title { plan.title = title }
        }
        guard comparable else {
            return .unavailable(String(localized: "This version has no text or title that fits this item, so it can only be read."))
        }
        return plan.isEmpty ? .unchanged : .ready(plan)
    }
}
