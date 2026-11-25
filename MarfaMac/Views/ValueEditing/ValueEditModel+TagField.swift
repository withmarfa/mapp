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
}
