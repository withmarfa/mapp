import Foundation
import Marfa

extension ValueEditModel {
    var tagRows: [ValueListRow] {
        let held = heldTokens
        let matching = library.tagSuggestions(matching: query, excluding: held)
        var rows: [ValueListRow] = []
        if !matching.isEmpty {
            rows += matching.prefix(30).map { ValueListRow(id: "tag:" + $0, role: .option, title: $0, mark: .tag) }
        }
        let typed = ItemTag.normalized(query)
        if !typed.isEmpty, !held.contains(typed), !library.knownTags.contains(typed) {
            rows.append(ValueListRow(id: "create", role: .create, title: String(localized: "Create “\(typed)”"), detail: "↩", mark: .symbol("plus")))
        }
        return rows
    }

    func activateTag(_ id: String) {
        guard !request.targets.isEmpty else { return }
        let tag = id == "create" ? ItemTag.normalized(query) : String(id.dropFirst("tag:".count))
        if let refusal = library.addTag(tag, to: request.targets, undoManager: request.undoManager) {
            notice = refusal.message
        } else {
            notice = nil
            query = ""
            highlight = nil
        }
    }

    /// The Tags box ends other than at Escape: a tag typed and not yet added is added. One the library refuses is kept on
    /// the clipboard and told, so ending the field never drops what was typed.
    func finishTagField() {
        guard kind == .tags, !ItemTag.normalized(query).isEmpty else { return }
        submitTyped()
        guard !ItemTag.normalized(query).isEmpty else { return }
        request.library.notices.notKept(
            String(localized: "Tag Not Added"), text: query, reason: notice ?? String(localized: "The tag could not be added."))
    }
}
