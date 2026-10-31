import Foundation

/// Why the server did not take an icon for a type, in terms the picker can word for a person.
nonisolated enum TypeIconFailure: Error, Hashable, Sendable {
    case unreachable
    /// The key MAPP uses does not have `schema.write`, or no write on the type.
    case notPermitted
    case keyRefused
    /// The server refused the name or the type, with its own sentence.
    case refused(String)
    /// This library has no server to keep the choice.
    case unsupported
    case failed(String)

    var message: String {
        switch self {
        case .unreachable:
            String(localized: "MAPP can’t reach the server. Your icon choice needs the server, so try again once it’s back.")
        case .notPermitted:
            String(localized: "This connection can’t change the icon of a type. Ask whoever runs the server to allow it, or use a key that can.")
        case .keyRefused:
            String(localized: "The server didn’t accept MAPP’s key. Choose a new key in Settings.")
        case .refused(let reason):
            reason
        case .unsupported:
            String(localized: "This library doesn’t keep icon choices.")
        case .failed(let message):
            message
        }
    }
}

/// Where an owner's choice of icon for a type is kept: on the server, for every app. The working copy does not take
/// the change until its stream reopens, so the library holds the answer itself meanwhile.
nonisolated protocol TypeIconSource: Sendable {
    /// Sets the icon of `type` to the Iconify ID `icon`, or clears the owner's choice when it is nil. Answers the icon
    /// the type has afterwards: the choice, or, once cleared, the author's own, which is nil if the author set none.
    func setIcon(_ icon: String?, ofType type: TypeID) async throws(TypeIconFailure) -> String?
}

nonisolated extension Catalogue {
    /// The catalogue once the server has answered that `type` shows `icon`. A type that shows none takes its nearest
    /// ancestor's, and every subtype that showed the icon `type` had (it set none of its own) shows the new one.
    func choosingIcon(_ icon: String?, ofType type: TypeID) -> Catalogue {
        guard let old = itemTypes[type] else { return self }
        let before = old.icon
        var changed = self
        let effective = icon ?? inheritedIcon(above: type)
        changed.itemTypes[type]?.icon = effective
        for (id, info) in itemTypes where id != type && info.icon == before && descends(id, from: type) {
            changed.itemTypes[id]?.icon = effective
        }
        return changed
    }

    private func inheritedIcon(above type: TypeID) -> String? {
        var next = itemTypes[type]?.parent
        var seen: Set<TypeID> = [type]
        while let id = next, seen.insert(id).inserted {
            if let icon = itemTypes[id]?.icon { return icon }
            next = itemTypes[id]?.parent
        }
        return nil
    }

    private func descends(_ type: TypeID, from ancestor: TypeID) -> Bool {
        var next = itemTypes[type]?.parent
        var seen: Set<TypeID> = [type]
        while let id = next, seen.insert(id).inserted {
            if id == ancestor { return true }
            next = itemTypes[id]?.parent
        }
        return false
    }
}

/// The search over the icon IDs the picker offers. Only the name after the set's prefix is searched, so typing
/// "lucide" or "simple" does not match everything.
nonisolated enum IconNameSearch {
    /// The IDs whose name contains every word typed, in the order given, best first: a name that starts with the first
    /// word comes before one that merely contains it, then a name whose parts include a word exactly. Case, spaces and
    /// hyphens do not matter ("arrow up" finds `lucide:arrow-up`). Empty text finds every ID.
    static func matching(_ text: String, in ids: [String]) -> [String] {
        let words = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" }).map(String.init)
        guard !words.isEmpty else { return ids }
        var scored: [(id: String, score: Int, index: Int)] = []
        for (index, id) in ids.enumerated() {
            let name = name(of: id)
            let parts = name.split(separator: "-").map(String.init)
            guard words.allSatisfy({ name.contains($0) }) else { continue }
            var score = 0
            if name.hasPrefix(words[0]) { score += 2 }
            score += words.filter { parts.contains($0) }.count
            scored.append((id, score, index))
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.map(\.id)
    }

    /// The part of an ID after its set, such as `book-open` for `lucide:book-open`.
    static func name(of id: String) -> String {
        id.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id
    }

    /// The icon as people read it, such as "Book Open" for `lucide:book-open`.
    static func title(of id: String) -> String {
        name(of: id).split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
