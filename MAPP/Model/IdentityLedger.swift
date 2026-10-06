import Foundation

/// The identity of every note, file and folder in a notes folder, kept apart from the folder in the app's own
/// storage, so an item keeps its identifier across launches and renames, renames made while the app was closed
/// among them. An item is known again by its file's identity on its volume, then by where it is; anything known
/// by neither, a copy say, is new. A trashed note is known by its place in the bin.
///
/// The ledger only remembers: losing it costs nothing but the identifiers, which are made again once.
nonisolated struct IdentityLedger: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case note, file, folder
    }

    nonisolated struct Entry: Codable, Equatable, Sendable {
        var id: UUID
        var kind: Kind
        /// The file's document identifier, or its file identifier where it has none; nil on a volume whose
        /// identifiers do not last, where items are known by their paths alone.
        var fileID: UInt64?
        /// Where the item is, relative to the notes folder; nil while it is in the bin.
        var path: String?
        var binID: UUID?
        /// When the item was first found gone, so an item that comes back, from a save that takes the file away
        /// and writes it again or a checkout of another branch, is still itself.
        var missing: Date?
    }

    /// An item as a reading of the folder found it: where it is, or its place in the bin, and its file's identity.
    nonisolated struct Sighting: Equatable, Sendable {
        var kind: Kind
        var path: String?
        var fileID: UInt64?
        var binID: UUID?
    }

    /// How long an item found gone is remembered before its entry goes.
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    private(set) var entries: [Entry] = []

    /// The identifier of each item found, in the order given; no two items get the same one. Each entry goes to
    /// at most one item: first to one with both its file and its path, then its file alone where the item is
    /// still of its kind, then its path alone, then its file alone whatever the item now is. So a file renamed
    /// keeps its identifier even when another has taken its old name, while an editor's backup or temporary file,
    /// which holds the note's old file under another name, does not take the note's identifier when it is read
    /// beside the note's new file. What is matched is brought up to date, what was not found is marked gone, and
    /// what has been gone longer than `retention` is forgotten.
    mutating func identify(_ sightings: [Sighting], at now: Date, retention: TimeInterval = Self.retention) -> [UUID] {
        var ids = [UUID?](repeating: nil, count: sightings.count)
        var claimed = [Bool](repeating: false, count: entries.count)
        var byBin: [UUID: Int] = [:]
        var byFile: [Key<UInt64>: [Int]] = [:]
        var byPath: [Key<String>: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            if let binID = entry.binID {
                byBin[binID] = byBin[binID] ?? index
                continue
            }
            let isFolder = entry.kind == .folder
            if let fileID = entry.fileID { byFile[Key(isFolder: isFolder, value: fileID), default: []].append(index) }
            if let path = entry.path { byPath[Key(isFolder: isFolder, value: path), default: []].append(index) }
        }

        func claim(_ sighting: Int, _ entry: Int) {
            claimed[entry] = true
            ids[sighting] = entries[entry].id
            let seen = sightings[sighting]
            entries[entry].kind = seen.kind
            entries[entry].fileID = seen.fileID
            entries[entry].path = seen.path
            entries[entry].binID = seen.binID
            entries[entry].missing = nil
        }
        func pass(_ match: (Sighting) -> Int?) {
            for (index, sighting) in sightings.enumerated() where ids[index] == nil {
                if let entry = match(sighting) { claim(index, entry) }
            }
        }
        func free(_ candidates: [Int]?, where condition: (Entry) -> Bool = { _ in true }) -> Int? {
            candidates?.first { !claimed[$0] && condition(entries[$0]) }
        }

        pass { sighting in sighting.binID.flatMap { byBin[$0] }.flatMap { claimed[$0] ? nil : $0 } }
        pass { sighting in
            guard sighting.binID == nil, let fileID = sighting.fileID else { return nil }
            return free(byFile[Key(isFolder: sighting.kind == .folder, value: fileID)]) { $0.path == sighting.path }
        }
        pass { sighting in
            guard sighting.binID == nil, let fileID = sighting.fileID else { return nil }
            return free(byFile[Key(isFolder: sighting.kind == .folder, value: fileID)]) { $0.kind == sighting.kind }
        }
        pass { sighting in
            guard sighting.binID == nil, let path = sighting.path else { return nil }
            return free(byPath[Key(isFolder: sighting.kind == .folder, value: path)])
        }
        pass { sighting in
            guard sighting.binID == nil, let fileID = sighting.fileID else { return nil }
            return free(byFile[Key(isFolder: sighting.kind == .folder, value: fileID)])
        }

        var kept: [Entry] = []
        kept.reserveCapacity(entries.count)
        for (index, var entry) in entries.enumerated() {
            if !claimed[index] {
                let since = entry.missing ?? now
                guard now.timeIntervalSince(since) < retention else { continue }
                entry.missing = since
            }
            kept.append(entry)
        }
        entries = kept
        return sightings.indices.map { index in
            if let id = ids[index] { return id }
            let sighting = sightings[index]
            let entry = Entry(id: UUID(), kind: sighting.kind, fileID: sighting.fileID, path: sighting.path, binID: sighting.binID)
            entries.append(entry)
            return entry.id
        }
    }

    private struct Key<Value: Hashable>: Hashable {
        let isFolder: Bool
        let value: Value
    }

    // MARK: Changes the app makes

    /// An item the app made, under the identifier it gave it. Anything remembered as gone from the same place
    /// gives way to it.
    mutating func record(_ id: UUID, kind: Kind, path: String, fileID: UInt64?) {
        let isFolder = kind == .folder
        entries.removeAll { $0.id == id || ($0.binID == nil && $0.path == path && ($0.kind == .folder) == isFolder) }
        entries.append(Entry(id: id, kind: kind, fileID: fileID, path: path))
    }

    /// An item moved by the app; a folder takes everything in it along.
    mutating func move(from old: String, to new: String, isFolder: Bool = false) {
        guard old != new else { return }
        entries.removeAll { $0.binID == nil && $0.path == new && ($0.kind == .folder) == isFolder && $0.missing != nil }
        for index in entries.indices where entries[index].binID == nil {
            guard let path = entries[index].path else { continue }
            if path == old, (entries[index].kind == .folder) == isFolder {
                entries[index].path = new
            } else if isFolder, path.hasPrefix(old + "/") {
                entries[index].path = new + path.dropFirst(old.count)
            }
        }
    }

    /// The file at a path was replaced whole, which gives it a new file identity when it has no document
    /// identifier.
    mutating func update(_ path: String, fileID: UInt64?) {
        guard let fileID,
              let index = entries.firstIndex(where: { $0.binID == nil && $0.path == path && $0.kind != .folder && $0.missing == nil })
        else { return }
        entries[index].fileID = fileID
    }

    /// The note at a path went into the bin.
    mutating func trash(_ path: String, binID: UUID) {
        guard let index = entries.firstIndex(where: { $0.binID == nil && $0.path == path && $0.kind != .folder && $0.missing == nil })
        else { return }
        entries[index].path = nil
        entries[index].binID = binID
    }

    /// The note in the bin came back to a path.
    mutating func restore(_ binID: UUID, to path: String, fileID: UInt64?) {
        guard let index = entries.firstIndex(where: { $0.binID == binID }) else { return }
        let id = entries[index].id
        record(id, kind: entries[index].kind, path: path, fileID: fileID ?? entries[index].fileID)
    }

    /// Notes erased from the bin for good.
    mutating func purge(_ binIDs: Set<UUID>) {
        entries.removeAll { $0.binID.map(binIDs.contains) == true }
    }
}
