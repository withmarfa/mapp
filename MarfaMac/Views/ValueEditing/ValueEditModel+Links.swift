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

    /// An item the field links to now, as a chip shows it.
    struct HeldLink: Hashable {
        let id: ItemID
        let title: String
        let item: Item?
    }

    /// Asked for by Add to Collection for the items chosen: only the collections they may join are edited, each item
    /// judged by the library, which tells the person which it left alone. A row on the page names one item and one field.
    var isBatch: Bool { !request.items.isEmpty }

    /// The field as the library reads it now. Nil for the command's items, or where the item no longer has the field.
    var linkField: RelationField? {
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
    var heldLinks: [HeldLink] {
        if isBatch {
            let members = library.collectionMembers(request.targets).compactMap(library.item)
            guard let first = members.first else { return [] }
            let common = members.dropFirst().reduce(Set(first.collectionIDs)) { $0.intersection($1.collectionIDs) }
            return library.joinableCollections.filter { common.contains($0.id) }.map { HeldLink(id: $0.id, title: $0.displayTitle, item: $0) }
        }
        return linkField?.targets.compactMap { target in
            target.itemID.map { HeldLink(id: $0, title: target.isOpenable ? target.displayTitle : String(localized: "Item not found"), item: library.item($0)) }
        } ?? []
    }

    var linkChips: [ValueChip] {
        heldLinks.map { ValueChip(id: Self.linkPrefix + $0.id.rawValue, title: $0.title, mark: $0.item.map(mark(of:)) ?? .none) }
    }

    /// The items the list offers: those the field could link that it does not hold, in the order the library gives
    /// (by title) narrowed by what is typed, and for a field of one link, the way to open the one it holds.
    var linkRows: [ValueListRow] {
        let held = Set(heldLinks.map(\.id))
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = linkCandidates.filter { !held.contains($0.id) && (typed.isEmpty || $0.displayTitle.localizedStandardContains(typed)) }
        var rows = matching.prefix(Self.linkLimit).map { candidate in
            ValueListRow(
                id: Self.linkPrefix + candidate.id.rawValue, role: .option, title: candidate.displayTitle,
                detail: candidate.state == .archived ? String(localized: "Archived") : nil, mark: mark(of: candidate))
        }
        if matching.count > Self.linkLimit { rows.append(.header(String(localized: "Type to narrow the list"), id: "header:more")) }
        if holdsOne, typed.isEmpty, let current = heldLinks.first, let item = current.item {
            rows.append(.separator)
            rows.append(ValueListRow(id: Self.openID, role: .option, title: String(localized: "Open “\(item.displayTitle)”"), mark: .symbol("arrow.up.right")))
        }
        return rows
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
        change(item, field: field.field, adding: [target], removing: holdsOne ? held : [], label: library.item(target)?.displayTitle ?? "")
    }

    /// Takes one chip's link away.
    func removeLink(_ chip: ValueChip) {
        guard !isSaving, let target = linkTarget(of: chip.id) else { return }
        if isBatch {
            library.removeFromCollection(request.targets, target, undoManager: request.undoManager)
            return
        }
        guard let field = linkField, let item = request.item else { return }
        change(item, field: field.field, adding: [], removing: [target], label: chip.title)
    }

    /// Makes the change in one undo step. The library judges it and may have to ask the server, so the panel waits without
    /// holding anything up and says why when the change is refused, keeping what was typed. A change answered after the panel
    /// has closed is told as a notice instead.
    private func change(_ item: ItemID, field: String, adding: [ItemID], removing: [ItemID], label: String) {
        isSaving = true
        notice = nil
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
