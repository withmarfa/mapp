import Foundation
import Marfa

/// What the panel of one edge field (`ValueEditKind.relation`) lists, holds and does. The library judges every change
/// (`ItemLibrary.changeLinks`) and answers once the copy has taken or refused it, so the panel waits for that answer, and
/// a refusal is told in the panel, which stays.
extension ValueEditModel {
    /// The most items the list shows before the person narrows it by typing.
    static let linkLimit = 50
    static let linkPrefix = "link:"
    static let openID = "open"
    static let moreID = "more:links"
    static let noResultsID = "header:none"

    /// An item the field links to now, as a chip shows it.
    struct HeldLink: Hashable {
        let id: ItemID
        let title: String
        let item: Item?
    }

    /// Asked for by Add to Collection for the items chosen: only the collections they may join are edited, each item
    /// judged by the library, which tells the person which it left alone. A row on the page names one item and one field.
    var isBatch: Bool { !request.items.isEmpty }

    /// What the panel reads of the library's links, worked out once for each revision of the library: building the
    /// field puts every target through the index, and a keystroke reads it six to ten times.
    struct LinkReading {
        let membership: Int
        let names: Int
        let field: RelationField?
        let held: [HeldLink]
    }

    var linkReading: LinkReading {
        let (membership, names) = (library.membershipRevision, library.namesRevision)
        if let cached = linkReadingCache, cached.membership == membership, cached.names == names { return cached }
        let field = readLinkField()
        let reading = LinkReading(membership: membership, names: names, field: field, held: readHeldLinks(of: field))
        linkReadingCache = reading
        return reading
    }

    /// The field as the library reads it now. Nil for the command's items, or where the item no longer has the field.
    var linkField: RelationField? { linkReading.field }

    private func readLinkField() -> RelationField? {
        guard case .relation(let name) = kind, !isBatch, let id = request.item else { return nil }
        return library.relationFields(of: id).first { $0.field == name }
    }

    /// Whether the panel can still change links: the library says so for a field, and for several items while any of
    /// them can be in a collection.
    var takesLinks: Bool {
        isBatch ? !library.collectionMembers(request.targets).isEmpty : linkField?.editability == .editable
    }

    /// Whether the field holds one link, which choosing another replaces and which closes the panel.
    var holdsOne: Bool { linkField?.cardinality == .one }

    /// Whether the far end can only be a collection, which the search field then asks for.
    var linksOnlyCollections: Bool {
        if isBatch { return true }
        guard let types = linkField?.allowedTypes, !types.isEmpty else { return false }
        return types.allSatisfy { library.catalogue.isCollection($0) }
    }

    /// The links the field holds now, which the search field shows as chips: for several items, the collections that
    /// every one of them is in.
    var heldLinks: [HeldLink] { linkReading.held }

    private func readHeldLinks(of field: RelationField?) -> [HeldLink] {
        if isBatch {
            let members = library.collectionMembers(request.targets).compactMap(library.item)
            guard let first = members.first else { return [] }
            let common = members.dropFirst().reduce(Set(first.collectionIDs)) { $0.intersection($1.collectionIDs) }
            return library.joinableCollections.filter { common.contains($0.id) }.map { HeldLink(id: $0.id, title: $0.displayTitle, item: $0) }
        }
        return field?.targets.compactMap { target in
            target.itemID.map { HeldLink(id: $0, title: target.isOpenable ? target.displayTitle : String(localized: "Item not found"), item: library.item($0)) }
        } ?? []
    }

    /// The chips of the links held: the first `PageHead.linkLimit`, then "N More", which shows the rest.
    var linkChips: [ValueChip] {
        let held = heldLinks
        let shown = showsAllLinks ? held[...] : held.prefix(PageHead.linkLimit)
        var chips = shown.map { ValueChip(id: Self.linkPrefix + $0.id.rawValue, title: $0.title, mark: $0.item.map(mark(of:)) ?? .none) }
        if held.count > shown.count {
            chips.append(ValueChip(id: Self.moreID, title: PageHead.moreLinksText(held.count - shown.count), isRemovable: false, revealsMore: true))
        }
        return chips
    }

    /// The items the list offers: those the field could link that it does not hold, in the order the library gives
    /// (by the name a row shows) narrowed by what is typed. A field of one link lists the link it holds first, lit, and
    /// the way to open it beside it, since the chip in the field is no row.
    var linkRows: [ValueListRow] {
        let held = heldLinks
        let heldIDs = Set(held.map(\.id))
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func fits(_ item: Item) -> Bool { typed.isEmpty || item.displayTitle.localizedStandardContains(typed) }
        let matching = linkCandidates.filter { !heldIDs.contains($0.id) && fits($0) }
        var rows: [ValueListRow] = []
        if holdsOne, let current = held.first, let item = current.item, fits(item) {
            var row = ValueListRow(
                id: Self.linkPrefix + item.id.rawValue, role: .option, title: item.displayTitle, detail: item.state == .archived ? String(localized: "Archived") : nil,
                mark: mark(of: item))
            row.isCurrent = true
            rows.append(row)
            if typed.isEmpty {
                rows.append(ValueListRow(id: Self.openID, role: .option, title: String(localized: "Open “\(item.displayTitle)”"), mark: .symbol("arrow.up.right")))
            }
            if !matching.isEmpty { rows.append(.separator) }
        }
        rows += matching.prefix(Self.linkLimit).map { candidate in
            ValueListRow(
                id: Self.linkPrefix + candidate.id.rawValue, role: .option, title: candidate.displayTitle,
                detail: detail(of: candidate), mark: mark(of: candidate))
        }
        if matching.count > Self.linkLimit { rows.append(.header(String(localized: "Type to narrow the list"), id: "header:more")) }
        if rows.isEmpty, !typed.isEmpty { rows.append(.header(String(localized: "No Results"), id: Self.noResultsID)) }
        return rows
    }

    /// What a row says beside its title: that the item is archived, and the item it would be taken from, where choosing
    /// it moves its one link (a child under another parent).
    private func detail(of candidate: Item) -> String? {
        let archived = candidate.state == .archived ? String(localized: "Archived") : nil
        guard let item = request.item, case .relation(let field) = kind,
            let holder = library.linkTakenFrom(candidate.id, field: field, for: item).flatMap(library.item)
        else { return archived }
        let holds = String(localized: "In \(holder.displayTitle)")
        return archived.map { String(localized: "\($0), \(holds)") } ?? holds
    }

    /// The item a row or a chip stands for.
    func linkTarget(of id: String) -> ItemID? {
        id.hasPrefix(Self.linkPrefix) ? ItemID(String(id.dropFirst(Self.linkPrefix.count))) : nil
    }

    /// Links the item chosen, which replaces the one a field of one link holds, or, for several items, files each in the
    /// collection and leaves it to the library to tell which it left alone.
    func activateLink(_ id: String) {
        guard !isSaving else { return }
        if id == Self.openID {
            if let target = heldLinks.first?.id { request.open(target) }
            close()
            return
        }
        guard let target = linkTarget(of: id) else { return }
        if isBatch {
            if library.addToCollection(request.targets, target, undoManager: request.undoManager) {
                query = ""
                highlight = nil
            }
            return
        }
        guard let field = linkField, let item = request.item else { return }
        let held = heldLinks.map(\.id)
        if held.contains(target) {
            if holdsOne { close() }
            return
        }
        let taken = library.linkTakenFrom(target, field: field.field, for: item).flatMap(library.item)?.displayTitle
        change(
            item, field: field.field, adding: [target], removing: holdsOne ? held : [],
            label: library.item(target)?.displayTitle ?? "", movedFrom: taken)
    }

    /// Takes one chip's link away.
    func removeLink(_ chip: ValueChip) {
        guard !isSaving, let target = linkTarget(of: chip.id) else { return }
        if isBatch {
            library.removeFromCollection(request.targets, target, undoManager: request.undoManager)
            return
        }
        guard let field = linkField, let item = request.item else { return }
        change(item, field: field.field, adding: [], removing: [target], label: chip.title, movedFrom: nil)
    }

    /// Makes the change in one undo step. The library judges it and may have to ask the server, so the panel waits without
    /// holding anything up and says why when the change is refused, keeping what was typed. A change answered after the panel
    /// has closed is told as a notice instead.
    private func change(_ item: ItemID, field: String, adding: [ItemID], removing: [ItemID], label: String, movedFrom: String?) {
        isSaving = true
        notice = nil
        moved = nil
        let (library, undoManager, closes) = (library, request.undoManager, holdsOne)
        Task { [weak self] in
            let verdict = await library.changeLinks(item, field: field, adding: adding, removing: removing, undoManager: undoManager)
            let reason = verdict.reason ?? String(localized: "The link could not be saved.")
            guard let self else {
                if verdict != .taken { library.notices.notKept(String(localized: "Link Not Saved"), text: label, reason: reason) }
                return
            }
            isSaving = false
            if verdict == .taken {
                moved = movedFrom.map { String(localized: "“\(label)” moved from “\($0)”.") }
                if closes {
                    close()
                } else {
                    query = ""
                    highlight = nil
                }
            } else if isFinished {
                library.notices.notKept(String(localized: "Link Not Saved"), text: label, reason: reason)
            } else {
                notice = reason
            }
        }
    }
}
