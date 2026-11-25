import Foundation
import Marfa

extension ValueEditModel {
    var heldWords: [String] { ListEntries.entries(of: value).compactMap(\.string) }

    var wordRows: [ValueListRow] {
        let held = Set(heldWords.map { $0.lowercased() })
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = wordPool.filter { entry in
            !held.contains(entry.word.lowercased()) && (typed.isEmpty || entry.word.localizedStandardContains(typed))
        }
        var rows: [ValueListRow] = matching.prefix(30).map {
            ValueListRow(id: "word:" + $0.word, role: .option, title: $0.word, detail: $0.count.formatted(), mark: .tag)
        }
        let known = held.contains(typed.lowercased()) || wordPool.contains { $0.word.lowercased() == typed.lowercased() }
        if !typed.isEmpty, !known {
            if !rows.isEmpty { rows.append(.separator) }
            rows.append(ValueListRow(id: "create", role: .create, title: String(localized: "Add “\(typed)”"), mark: .symbol("plus")))
        }
        return rows
    }

    func activateWord(_ id: String) {
        let word = id == "create" ? query.trimmingCharacters(in: .whitespacesAndNewlines) : String(id.dropFirst("word:".count))
        guard !word.isEmpty else { return }
        let held = heldWords
        guard !held.contains(where: { $0.lowercased() == word.lowercased() }) else {
            query = ""
            return
        }
        if let reason = limitReason(holding: held.count + 1) {
            refuse(reason, typed: isTypedEntry(id))
            return
        }
        if commitWords(held + [word]) {
            query = ""
            highlight = nil
        } else {
            refuse(notice, typed: isTypedEntry(id))
        }
    }

    @discardableResult
    func commitWords(_ words: [String]) -> Bool {
        commit(words.isEmpty ? nil : .array(words.map { .string($0) }), failure: String(localized: "The list could not be saved."))
    }
}
