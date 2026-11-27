import CryptoKit
import Foundation

/// How this Mac's settings and the Marfa's are brought together. Pure, so every case can be tested without a copy.
nonisolated enum PreferencesMerge {
    /// What a reconcile decided: the settings both sides hold after it, which of them this Mac must take, and which
    /// the Marfa must.
    struct Outcome: Equatable, Sendable {
        var merged: PreferenceUnits
        var toLocal: Set<PreferenceUnit> = []
        var toRemote: Set<PreferenceUnit> = []
    }

    /// Compares each setting on this Mac and in the Marfa with what both held after the last reconcile (`base`). A
    /// setting changed on one side only goes to the other. One changed on both sides to different values keeps this
    /// Mac's: it has not been written yet, so it is the later write. `frozen` names settings whose stored text this Mac
    /// cannot read, which neither side takes until the store has set it aside.
    static func reconcile(
        local: PreferenceUnits, remote: PreferenceUnits, base: PreferenceUnits,
        adopting: (PreferenceUnit) -> Bool = { _ in false },
        frozen: (PreferenceUnit) -> Bool = { _ in false }
    ) -> Outcome {
        var outcome = Outcome(merged: [:])
        for unit in Set(local.keys).union(remote.keys).union(base.keys) {
            let (mine, theirs, before) = (local[unit], remote[unit], base[unit])
            if adopting(unit) {
                // A returning member or row has no shared history. What the Marfa holds wins, even if a
                // local store cannot read it and another member makes us write the whole field.
                outcome.merged[unit] = theirs ?? mine
                if let theirs, theirs != mine, !frozen(unit) { outcome.toLocal.insert(unit) }
                if theirs == nil, mine != nil, !frozen(unit) { outcome.toRemote.insert(unit) }
                continue
            }
            if frozen(unit) {
                outcome.merged[unit] = before
                continue
            }
            switch (mine != before, theirs != before) {
            case (false, false):
                outcome.merged[unit] = before
            case (false, true):
                outcome.merged[unit] = theirs
                outcome.toLocal.insert(unit)
            case (true, false):
                outcome.merged[unit] = mine
                outcome.toRemote.insert(unit)
            case (true, true):
                outcome.merged[unit] = mine
                if mine != theirs { outcome.toRemote.insert(unit) }
            }
        }
        return outcome
    }

    /// Adopting an item another Mac made: what it holds wins, and what it lacks is filled from this Mac, once.
    static func adopt(remote: PreferenceUnits, local: PreferenceUnits) -> Outcome {
        reconcile(local: local, remote: remote, base: [:], adopting: { _ in true })
    }

    /// The settings of the item the app uses, with what it lacks filled from the others, in the order they were made.
    static func filling(_ first: PreferenceUnits, from others: [PreferenceUnits]) -> PreferenceUnits {
        others.reduce(into: first) { held, other in held.merge(other) { kept, _ in kept } }
    }

    /// The base to reconcile against when the server kept another Mac's value of a field and wrote this Mac's to a
    /// conflicted copy: each member this Mac sent (`conflicted` holds only those) and still holds counts as changed
    /// again, so it is written over the other's, while the members the other Mac changed come here. Only the same
    /// member's later write wins.
    static func base(_ base: PreferenceUnits, reclaiming conflicted: PreferenceUnits, local: PreferenceUnits,
                     remote: PreferenceUnits) -> PreferenceUnits
    {
        var adjusted = base
        for (unit, value) in conflicted where local[unit] == value && remote[unit] != value {
            adjusted[unit] = remote[unit]
        }
        return adjusted
    }

    /// The base to reconcile against when this Mac replaced settings on purpose (an import, a restore, Reset): each
    /// unit `wins` names where this Mac's value differs from the Marfa's counts as changed here and unchanged there, so
    /// this Mac's value is written, even over another Mac's change this Mac had not taken.
    static func base(_ base: PreferenceUnits, winning wins: (PreferenceUnit) -> Bool, local: PreferenceUnits,
                     remote: PreferenceUnits) -> PreferenceUnits
    {
        var adjusted = base
        for unit in Set(local.keys).union(remote.keys).union(base.keys) where wins(unit) && local[unit] != remote[unit] {
            adjusted[unit] = remote[unit]
        }
        return adjusted
    }

    /// A row's id: the same on every Mac for the same table, setting and key, so two Macs writing one setting write one
    /// row. Shaped as the lowercase UUIDv7 a row id must be, from a hash rather than a time.
    static func rowID(_ table: PreferencesTable, setting: String, key: String) -> String {
        var bytes = Array(SHA256.hash(data: Data("\(table.rawValue)\u{0}\(setting)\u{0}\(key)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4), hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
        return parts.joined(separator: "-")
    }
}
