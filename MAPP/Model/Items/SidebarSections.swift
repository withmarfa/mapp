import Foundation

/// A section of the right sidebar, which Customize Layout lets a person order, remove and add for a type. Its
/// identifier is what `PagePlacements` stores.
nonisolated enum SidebarSection: Hashable, Sendable {
    case details, properties, relationships, linksInPage, linkedFrom, tags
    /// The headings of the note's text.
    case outline
    /// The files attached to the item.
    case attachments
    /// The collections the item is in.
    case collections
    /// The items linked to this one that a connector's source made, of one type: `Pull Requests (GitHub)`.
    case app(type: TypeID, source: String)

    private static let appPrefix = "app:"

    var id: String {
        switch self {
        case .details: "details"
        case .properties: "properties"
        case .relationships: "relationships"
        case .linksInPage: "links-in-page"
        case .linkedFrom: PagePlacement.linkedFrom
        case .tags: "tags"
        case .outline: "outline"
        case .attachments: "attachments"
        case .collections: "collections"
        case .app(let type, let source): "\(Self.appPrefix)\(type.rawValue)|\(source)"
        }
    }

    init?(id: String) {
        switch id {
        case "details": self = .details
        case "properties": self = .properties
        case "relationships": self = .relationships
        case "links-in-page": self = .linksInPage
        case PagePlacement.linkedFrom: self = .linkedFrom
        case "tags": self = .tags
        case "outline": self = .outline
        case "attachments": self = .attachments
        case "collections": self = .collections
        default:
            guard id.hasPrefix(Self.appPrefix) else { return nil }
            let parts = id.dropFirst(Self.appPrefix.count).split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            self = .app(type: TypeID(String(parts[0])), source: String(parts[1]))
        }
    }

    /// The sections a type shows before anyone arranges them, in order.
    static let defaults: [SidebarSection] = [.details, .properties, .relationships, .linksInPage, .linkedFrom, .tags]
    static let defaultIDs = defaults.map(\.id)

    /// Every section that is not from an app, in the order Add Section lists them.
    static let builtIn: [SidebarSection] = [.details, .properties, .relationships, .linksInPage, .linkedFrom, .tags, .outline, .attachments, .collections]

    var isFromApp: Bool {
        if case .app = self { true } else { false }
    }

    /// The system symbol of a built-in section. An app's section is drawn with its type's icon instead.
    var symbol: String {
        switch self {
        case .details: "info.circle"
        case .properties: "list.bullet"
        case .relationships: "point.3.connected.trianglepath.dotted"
        case .linksInPage: "link"
        case .linkedFrom: "arrow.down.left"
        case .tags: "tag"
        case .outline: "list.bullet.indent"
        case .attachments: "paperclip"
        case .collections: "rectangle.stack"
        case .app: "square.grid.2x2"
        }
    }

    /// The name of a built-in section; an app's is `title(in:sources:)`.
    var title: String {
        switch self {
        case .details: String(localized: "Details")
        case .properties: String(localized: "Properties")
        case .relationships: String(localized: "Relationships")
        case .linksInPage: String(localized: "Links in This Page")
        case .linkedFrom: String(localized: "Linked From")
        case .tags: String(localized: "Tags")
        case .outline: String(localized: "Outline")
        case .attachments: String(localized: "Attachments")
        case .collections: String(localized: "Collections")
        case .app: ""
        }
    }

    /// The name of any section: an app's is its type's plural with the source's name.
    func title(in catalogue: Catalogue, sources: SourceDirectory) -> String {
        guard case .app(let type, let source) = self else { return title }
        return "\(catalogue.plural(for: type)) (\(sources.name(source)))"
    }
}

/// A heading of a note's text, for the Outline section.
nonisolated struct OutlineHeading: Identifiable, Hashable, Sendable {
    let level: Int
    let text: String
    /// The position among the headings, since two headings can read the same.
    let index: Int
    var id: Int { index }
}

nonisolated extension OutlineHeading {
    /// The headings of `text`, in order: ATX headings (`#` to `######`, a space, the words), skipping a front matter
    /// block and fenced code, which hold lines that only look like headings. Read for the one note on the page, never
    /// for the library.
    static func headings(in text: String) -> [OutlineHeading] {
        var result: [OutlineHeading] = []
        var fence: Substring?
        var lineNumber = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            defer { lineNumber += 1 }
            let line = line.hasSuffix("\r") ? line.dropLast() : line
            if lineNumber == 0, line == "---" {
                fence = "---"
                continue
            }
            if let open = fence {
                if open == "---" ? (line == "---" || line == "...") : line.trimmingCharacters(in: .whitespaces).hasPrefix(open) {
                    fence = nil
                }
                continue
            }
            let trimmed = line.drop { $0 == " " }
            if line.count - trimmed.count <= 3, trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = trimmed.prefix(3)
                continue
            }
            if line.count - trimmed.count > 3 { continue }
            let hashes = trimmed.prefix { $0 == "#" }
            guard (1...6).contains(hashes.count) else { continue }
            let rest = trimmed.dropFirst(hashes.count)
            guard rest.first == " " || rest.first == "\t" else { continue }
            var words = rest.trimmingCharacters(in: .whitespaces)
            // A closing run of hashes is part of the syntax, not of the heading.
            if let closing = words.range(of: #"\s+#+$"#, options: .regularExpression) { words.removeSubrange(closing) }
            if words.allSatisfy({ $0 == "#" }) { words = "" }
            guard !words.isEmpty else { continue }
            result.append(OutlineHeading(level: hashes.count, text: words, index: result.count))
        }
        return result
    }
}

/// What a connector's source gave an item's type: the items linked to it, of one type, from one source.
nonisolated struct AppSection: Identifiable, Equatable, Sendable {
    let section: SidebarSection
    /// The type's plural with the source's name, as `Pull Requests (GitHub)`.
    let title: String
    /// The type's icon.
    let icon: String?
    let sourceName: String
    let targets: [ItemRelationshipTarget]
    var id: String { section.id }

    static func == (lhs: AppSection, rhs: AppSection) -> Bool {
        lhs.section == rhs.section && lhs.title == rhs.title && lhs.targets.map(\.id) == rhs.targets.map(\.id)
    }
}

/// What the sections that need more than the inspector already reads hold for one item. Read from the library for the
/// item on the page, and only when a person has the section: nothing here is parsed for every note.
nonisolated struct SidebarExtras: Sendable {
    var outline: [OutlineHeading] = []
    var attachments: [ItemRelationshipTarget] = []
    var collections: [ItemRelationshipTarget] = []
    /// The sections an app's data gives the item, by title.
    var apps: [AppSection] = []

    func count(of section: SidebarSection) -> Int? {
        switch section {
        case .outline: outline.count
        case .attachments: attachments.count
        case .collections: collections.count
        case .app: apps.first { $0.section == section }?.targets.count ?? 0
        default: nil
        }
    }

    /// The headings, files, collections and app items of `item`. An app's section is made of the items its
    /// relationships reach whose type a connector declares (a type with a link field) and whose source is named: real
    /// edges and real sources, so an item with none has none. Only what `sections` names is read (all, where nil), so a
    /// note's text is scanned only while its Outline is in the sidebar.
    @MainActor
    static func of(_ item: Item, in library: any ItemLibrary, relationships: [ItemRelationship], sections: [SidebarSection]? = nil) -> SidebarExtras {
        var extras = SidebarExtras()
        func wants(_ section: SidebarSection) -> Bool { sections?.contains(section) ?? true }
        if wants(.outline), !item.isFile, let body = library.body(of: item.id) { extras.outline = OutlineHeading.headings(in: body.text) }
        if wants(.attachments) { extras.attachments = library.attachments(of: item.id).compactMap { library.item($0) }.map(target) }
        if wants(.collections) { extras.collections = library.collections(holding: [item.id]).map(target) }
        guard sections?.contains(where: \.isFromApp) ?? true else { return extras }

        var seen: Set<ItemID> = []
        var groups: [SidebarSection: [ItemRelationshipTarget]] = [:]
        for relationship in relationships {
            for found in relationship.targets {
                guard let id = found.itemID, found.isOpenable, id != item.id, seen.insert(id).inserted,
                      let other = library.item(id), let source = other.source, !source.isEmpty,
                      library.catalogue.itemTypes[other.type]?.linkField != nil
                else { continue }
                groups[.app(type: other.type, source: source), default: []].append(found)
            }
        }
        extras.apps = groups.map { section, targets in
            guard case .app(let type, let source) = section else { preconditionFailure("an app section") }
            return AppSection(
                section: section, title: section.title(in: library.catalogue, sources: library.sources),
                icon: library.catalogue.icon(for: type), sourceName: library.sources.name(source), targets: targets)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return extras
    }

    private static func target(_ item: Item) -> ItemRelationshipTarget {
        ItemRelationshipTarget(
            title: item.name ?? "", itemID: item.id, resolution: .resolved(item.id), isDeleted: item.state == .trashed)
    }
}
