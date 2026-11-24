import Foundation
import Marfa

extension ValueEditModel {
    var heldWords: [String] { ListEntries.entries(of: value).compactMap(\.string) }

    var wordRows: [ValueListRow] {
        let held = Set(heldWords.map { $0.lowercased() })
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = wordPool.filter { word in
            !held.contains(word.lowercased()) && (typed.isEmpty || word.localizedStandardContains(typed))
        }
        var rows: [ValueListRow] = []
        if !matching.isEmpty {
            rows += matching.prefix(30).map { ValueListRow(id: "word:" + $0, role: .option, title: $0, mark: .tag) }
        }
        let known = held.contains(typed.lowercased()) || wordPool.contains { $0.lowercased() == typed.lowercased() }
        if !typed.isEmpty, !known {
            rows.append(ValueListRow(id: "create", role: .create, title: String(localized: "Add “\(typed)”"), detail: "↩", mark: .symbol("plus")))
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
            notice = reason
            return
        }
        if commitWords(held + [word]) {
            query = ""
            highlight = nil
        }
    }

    @discardableResult
    func commitWords(_ words: [String]) -> Bool {
        commit(words.isEmpty ? nil : .array(words.map { .string($0) }), failure: String(localized: "The list could not be saved."))
    }
}
