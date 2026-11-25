import Foundation
import Marfa

extension ValueEditModel {
    var tagRows: [ValueListRow] {
        let held = heldTokens
        let matching = library.tagSuggestions(matching: query, excluding: held)
        let counts = library.knownTagCounts
        var rows: [ValueListRow] = matching.prefix(30).map {
            ValueListRow(id: "tag:" + $0, role: .option, title: $0, detail: counts[$0]?.formatted(), mark: .tag)
        }
        let typed = ItemTag.normalized(query)
        if !typed.isEmpty, !held.contains(typed), counts[typed] == nil {
            if !rows.isEmpty { rows.append(.separator) }
            rows.append(ValueListRow(id: "create", role: .create, title: String(localized: "Create Tag “\(typed)”")))
        }
        return rows
    }

    func activateTag(_ id: String) {
        guard !request.targets.isEmpty else { return }
        let tag = id == "create" ? ItemTag.normalized(query) : String(id.dropFirst("tag:".count))
        if let refusal = library.addTag(tag, to: request.targets, undoManager: request.undoManager) {
            refuse(refusal.message, typed: isTypedEntry(id))
        } else {
            notice = nil
            query = ""
            highlight = nil
        }
    }

    /// The Tags box ends other than at Escape: a tag typed and not yet added is added. One the library refuses is kept on
    /// the clipboard and told, once, so ending the field never drops what was typed.
    func finishTagField() {
        guard kind == .tags else { return }
        if !ItemTag.normalized(query).isEmpty {
            submitTyped()
            // The box ends here, so a tag it still holds was not added, whichever row Return chose.
            if unsaved == nil, !ItemTag.normalized(query).isEmpty { refuse(notice ?? String(localized: "The tag could not be added."), typed: true) }
        }
        handBackUnsaved()
    }
}
