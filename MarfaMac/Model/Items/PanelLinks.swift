import Foundation

/// The groups of the panel's Links for one item, made from edges the copy already holds: nothing is asked of the server.
nonisolated enum PanelLinks {
    private static let inversePrefix = "inverse:"
    /// Marfa's edge types that give a group its own place, so Referenced By does not list them again. A child is at the
    /// page's foot, a collection's member is its content, and a file is an attachment.
    private static let leftToOtherGroups: Set<String> = [
        MarfaMapping.parentEdge, MarfaMapping.collectionEdge, MarfaMapping.excerptEdge, MarfaMapping.threadEdge,
        MarfaMapping.attachmentEdge, MarfaMapping.placementEdge,
    ]

    /// The item's own link of the edge type `edge`, as the relationships name it.
    private static func own(_ edge: String, in relationships: [ItemRelationship]) -> [ItemRelationshipTarget] {
        relationships.first { $0.field == edge }?.targets ?? []
    }

    private static func inverse(_ edge: String, in relationships: [ItemRelationship]) -> [ItemRelationshipTarget] {
        relationships.first { $0.field == inversePrefix + edge }?.targets ?? []
    }

    /// The groups the item has, in the order the panel draws them. A group with no link is left out.
    @MainActor
    static func groups(
        of item: Item, in library: any ItemLibrary, relationships: [ItemRelationship], mentions: [ItemRelationshipTarget],
        format: DateFormat
    ) -> [PanelLinkGroup] {
        let now = library.now()
        func link(_ held: Item, detail: String? = nil) -> PanelLink {
            PanelLink(
                item: held.id, title: held.displayTitle, icon: library.catalogue.icon(for: held.type),
                status: status(of: held, in: library.catalogue),
                detail: detail ?? DateDisplay.text(of: held.modified, place: .list, format: format, now: now),
                isCurrent: held.id == item.id)
        }
        func links(_ targets: [ItemRelationshipTarget], newestFirst: Bool = true, keepingSelf: Bool = false) -> [PanelLink] {
            var seen: Set<ItemID> = keepingSelf ? [] : [item.id]
            let held = targets.compactMap { target -> Item? in
                guard let id = target.itemID, !target.isDeleted, let held = library.headerItem(id), held.state == .active,
                      seen.insert(id).inserted else { return nil }
                return held
            }
            return held
                .sorted { $0.modified != $1.modified ? ($0.modified > $1.modified) == newestFirst : $0.title < $1.title }
                .map { link($0) }
        }

        var result: [PanelLinkGroup] = []
        let fields = library.relationFields(of: item.id)
        func add(_ kind: PanelLinkGroup.Kind, _ links: [PanelLink], field: String? = nil) {
            guard !links.isEmpty else { return }
            let editable = field.flatMap { name in fields.first { $0.field == name && $0.editability == .editable } }?.field
            result.append(PanelLinkGroup(kind: kind, links: links, editableField: editable))
        }

        let collections = item.collectionIDs.compactMap { library.headerItem($0) }
            .filter { $0.state == .active && library.catalogue.isCollection($0.type) }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        add(.inCollection, collections.map { link($0, detail: "") }, field: MarfaMapping.collectionEdge)

        let referencing = relationships.filter {
            $0.field.hasPrefix(inversePrefix) && !leftToOtherGroups.contains(String($0.field.dropFirst(inversePrefix.count)))
        }
        add(.referencedBy, links(referencing.flatMap(\.targets)))
        add(.linksInText, links(mentions, newestFirst: false))
        add(.excerpts, links(inverse(MarfaMapping.excerptEdge, in: relationships)), field: inversePrefix + MarfaMapping.excerptEdge)

        let books = own(MarfaMapping.excerptEdge, in: relationships).compactMap(\.itemID)
        var fellows: [ItemRelationshipTarget] = []
        for book in books { fellows += inverse(MarfaMapping.excerptEdge, in: library.relationships(for: book)) }
        add(.moreFromBook, links(fellows))

        // A message's thread lists every message in it, this one in semibold.
        var thread: [ItemRelationshipTarget] = []
        for owner in own(MarfaMapping.threadEdge, in: relationships).compactMap(\.itemID) {
            thread += inverse(MarfaMapping.threadEdge, in: library.relationships(for: owner))
        }
        add(.thread, links(thread, keepingSelf: true))

        let files = library.attachments(of: item.id).compactMap { library.headerItem($0) }
            .filter { $0.state == .active }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        add(.attachments, files.map { held in
            guard case .file(_, let bytes) = held.content, bytes > 0 else { return link(held) }
            return link(held, detail: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }, field: inversePrefix + MarfaMapping.attachmentEdge)
        return result
    }

    /// A task shows its status mark, never its type's: the group of the item's status word, where its type has a status.
    static func status(of item: Item, in catalogue: Catalogue) -> StatusGroup? {
        guard let field = catalogue.itemTypes[item.type]?.statusField, let word = item.value(of: field.key)?.string, !word.isEmpty
        else { return nil }
        return field.statusGroup(of: word)
    }
}
