import Foundation
import Marfa

extension ValueEditModel {
    /// The parent the item has now, if any.
    var parentTarget: ItemRelationshipTarget? {
        request.item.flatMap { library.relationships(for: $0).first { $0.field == PagePlacement.parent }?.targets.first }
    }

    /// The most items the parent's list shows before the person narrows it by typing.
    static let parentLimit = 50
    static let openID = "open"

    var parentRows: [ValueListRow] {
        var rows: [ValueListRow] = []
        let current = parentTarget
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentID = current?.itemID
        let matching = parentCandidates.filter { $0.id != currentID && (typed.isEmpty || $0.title.localizedStandardContains(typed)) }
        if !matching.isEmpty {
            rows += matching.prefix(Self.parentLimit).map {
                ValueListRow(id: "parent:" + $0.id.rawValue, role: .option, title: $0.displayTitle, detail: library.catalogue.label(for: $0.type))
            }
            if matching.count > Self.parentLimit {
                rows.append(.header(String(localized: "Type to narrow the list"), id: "header:more"))
            }
        }
        if typed.isEmpty, let current, current.itemID != nil, current.isOpenable {
            rows.append(.separator)
            rows.append(ValueListRow(id: Self.openID, role: .option, title: String(localized: "Open “\(current.displayTitle)”"), mark: .symbol("arrow.up.right")))
        }
        return rows
    }

    func activateParent(_ id: String) {
        guard !isSaving, let item = request.item else { return }
        let current = parentTarget
        switch id {
        case Self.openID:
            if let target = current?.itemID { request.open(target) }
            close()
        default:
            let target = ItemID(String(id.dropFirst("parent:".count)))
            if target == current?.itemID { close() } else { changeParent(of: item, adding: target, removing: current?.itemID) }
        }
    }

    /// Replaces the parent. The library judges the link, and may have to ask the server, so the panel waits without
    /// holding anything up and says why when the change is refused. A change that is answered after the panel has
    /// closed is told as a notice instead.
    func changeParent(of item: ItemID, adding: ItemID?, removing: ItemID?) {
        isSaving = true
        notice = nil
        let (library, undoManager) = (library, request.undoManager)
        let label = adding.flatMap(library.item)?.displayTitle ?? parentTarget?.displayTitle ?? ""
        Task { [weak self] in
            var refusal: String?
            if let adding, case .refused(let message) = await library.relationshipVerdict(for: item, field: PagePlacement.parent, to: adding) {
                refusal = message
            }
            let taken: Bool
            if refusal == nil {
                taken = await library.changeItemRelationship(
                    item, field: PagePlacement.parent, adding: adding.map { [$0] } ?? [], removing: removing.map { [$0] } ?? [], undoManager: undoManager)
            } else {
                taken = false
            }
            guard let self else {
                if !taken { library.notices.notKept(String(localized: "Parent Not Saved"), text: label, reason: refusal ?? String(localized: "The parent could not be saved.")) }
                return
            }
            isSaving = false
            if taken {
                close()
            } else if isFinished {
                library.notices.notKept(String(localized: "Parent Not Saved"), text: label, reason: refusal ?? String(localized: "The parent could not be saved."))
            } else {
                notice = refusal ?? String(localized: "The parent could not be saved.")
            }
        }
    }
}
