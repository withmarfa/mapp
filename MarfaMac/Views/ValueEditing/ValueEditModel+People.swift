import Foundation
import Marfa

extension ValueEditModel {
    func peopleRows(_ shape: ListShape) -> [ValueListRow] {
        let held = PeopleSuggestions.held(in: value, shape: shape)
        let matching = PeopleSuggestions.matching(query, in: pool, excluding: held)
        func mark(_ person: PeopleSuggestions.Person) -> ValueListRow.Mark { .person(initials: PersonInitials.of(person.name) ?? "") }
        // Two people can share a name; their address then tells them apart.
        let names = Dictionary(grouping: held.map(\.person) + matching, by: { $0.name.lowercased() }).mapValues(\.count)
        func detail(_ person: PeopleSuggestions.Person) -> String? { names[person.name.lowercased(), default: 0] > 1 ? person.address : nil }
        var rows: [ValueListRow] = []
        if !matching.isEmpty {
            rows += matching.prefix(30).map {
                ValueListRow(id: "person:" + $0.identity, role: .option, title: $0.name, detail: detail($0), mark: mark($0))
            }
        }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let known = (held.map(\.person) + pool).contains { $0.isNamed(typed) }
        if !typed.isEmpty, !known {
            rows.append(ValueListRow(id: "create", role: .create, title: String(localized: "Add “\(typed)”"), detail: "↩", mark: .symbol("plus")))
        }
        return rows
    }

    func activatePerson(_ id: String, _ shape: ListShape) {
        let held = PeopleSuggestions.held(in: value, shape: shape)
        if id.hasPrefix(PeopleSuggestions.Held.prefix) {
            // The index is the entry's place in the stored list, which holds entries `held` cannot read too.
            guard let person = held.first(where: { $0.id == id }) else { return }
            _ = commit(ListEntries.removing(at: person.index, from: value), failure: String(localized: "The list could not be saved."))
            return
        }
        let entry: ListEntries.Entry?
        if id == "create" {
            entry = PeopleSuggestions.entry(from: query, shape: shape)
        } else {
            entry = pool.first { "person:" + $0.identity == id }?.entry
        }
        guard let entry else { return }
        if let refusal = shape.refusal(of: entry) {
            notice = refusal
            return
        }
        // A tap on a row that was held by the last one is not a second person.
        if let person = PeopleSuggestions.Person(entry: entry, shape: shape), held.contains(where: { $0.person.identity == person.identity }) {
            query = ""
            return
        }
        if let reason = limitReason(holding: ListEntries.entries(of: value).count + 1) {
            notice = reason
            return
        }
        if commit(ListEntries.appending(entry, to: value), failure: String(localized: "The list could not be saved.")) {
            query = ""
            highlight = nil
        }
    }
}
