import Foundation
import Marfa

/// The changes to saved views that could not reach the server, kept on this Mac until it can. A window keeps the change
/// it holds for a view here as it makes it offline, so leaving the view, closing the window or quitting loses nothing,
/// and a write that lands takes it away. Once the server can be reached, `send(in:defaults:)` writes each change no open
/// window is about to write itself, whatever the windows show.
///
/// Each view's change is held by setting (its query, sort and group), each with the window that made it and the version
/// it was made on, so two windows that change different settings offline both keep theirs. A window's later change
/// replaces only what that window held, and the settings it no longer changes are taken away.
///
/// A change is sent on the oldest version its settings were made on, so the server merges it with what another app
/// changed meanwhile, or refuses it where they changed the same setting (`views/change-conflict`). A change the server
/// refuses is given back on the clipboard (`Notices.notKept`), in words the person can make it again from.
@MainActor
enum PendingViewChanges {
    nonisolated enum Setting: String, Codable, Hashable, Sendable, CaseIterable {
        case query, sort, group
    }

    nonisolated struct Entry: Codable, Hashable, Sendable {
        /// The change of this one setting.
        var change: LibraryViewChange
        var baseVersion: Int64
        /// The window that made it (`Browser.pendingOwner`).
        var owner: String
    }

    nonisolated struct Pending: Codable, Hashable, Sendable {
        var entries: [Setting: Entry] = [:]

        /// Every setting's change as one.
        var change: LibraryViewChange {
            var change = LibraryViewChange()
            for entry in entries.values {
                if let query = entry.change.query { change.query = query }
                if let sort = entry.change.sort { change.sort = sort }
                if let group = entry.change.group { change.group = group }
            }
            return change
        }

        var baseVersion: Int64 { entries.values.map(\.baseVersion).min() ?? 0 }

        /// The settings `owner` made.
        func made(by owner: String) -> Pending {
            Pending(entries: entries.filter { $0.value.owner == owner })
        }
    }

    /// One value in the defaults, by view identifier. It stays on this Mac: it is no setting, and syncs nowhere.
    static let key = "pendingViewChanges"

    /// The views being sent now, so two windows that see the server come back send each once.
    private static var sending: Set<ItemID> = []

    static func stored(in defaults: UserDefaults) -> [ItemID: Pending] {
        guard let data = defaults.data(forKey: key), let held = try? JSONDecoder().decode([String: Pending].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: held.map { (ItemID($0.key), $0.value) })
    }

    /// A change in its settings, each alone.
    static func settings(of change: LibraryViewChange) -> [Setting: LibraryViewChange] {
        var settings: [Setting: LibraryViewChange] = [:]
        if let query = change.query { settings[.query] = LibraryViewChange(query: query) }
        if let sort = change.sort { settings[.sort] = LibraryViewChange(sort: sort) }
        if let group = change.group { settings[.group] = LibraryViewChange(group: group) }
        return settings
    }

    /// Keeps the whole change a window holds for a view: it replaces what that window kept before, and any other
    /// window's change of the same settings, and leaves every other setting another window kept.
    static func keep(_ change: LibraryViewChange, baseVersion: Int64, for id: ItemID, by owner: String, in defaults: UserDefaults) {
        update(in: defaults) { held in
            var pending = held[id] ?? Pending()
            pending.entries = pending.entries.filter { $0.value.owner != owner }
            for (setting, part) in settings(of: change) {
                pending.entries[setting] = Entry(change: part, baseVersion: baseVersion, owner: owner)
            }
            held[id] = pending.entries.isEmpty ? nil : pending
        }
    }

    /// Takes away what `owner` kept for a view, or every window's where `owner` is nil.
    static func forget(_ id: ItemID, by owner: String? = nil, in defaults: UserDefaults) {
        guard let pending = stored(in: defaults)[id] else { return }
        let left = owner.map { owner in pending.entries.filter { $0.value.owner != owner } } ?? [:]
        guard left != pending.entries else { return }
        update(in: defaults) { $0[id] = left.isEmpty ? nil : Pending(entries: left) }
    }

    /// Takes away exactly these entries, and leaves any a window kept since.
    private static func forget(_ sent: Pending, of id: ItemID, in defaults: UserDefaults) {
        guard var pending = stored(in: defaults)[id] else { return }
        for (setting, entry) in sent.entries where pending.entries[setting] == entry { pending.entries[setting] = nil }
        update(in: defaults) { $0[id] = pending.entries.isEmpty ? nil : pending }
    }

    static func holds(_ id: ItemID, in defaults: UserDefaults) -> Bool {
        stored(in: defaults)[id] != nil
    }

    static func isSending(_ id: ItemID) -> Bool {
        sending.contains(id)
    }

    private static func update(in defaults: UserDefaults, _ change: (inout [ItemID: Pending]) -> Void) {
        var held = stored(in: defaults)
        change(&held)
        guard !held.isEmpty else { return defaults.removeObject(forKey: key) }
        let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: held.map { ($0.key.rawValue, $0.value) }))
        defaults.set(data, forKey: key)
    }

    /// Sends each change kept for a view the library holds, but one that an open window shows with the change still in
    /// it, which that window writes itself. A change kept for a view another server holds waits for that server.
    static func send(in library: any ItemLibrary, defaults: UserDefaults) async {
        guard library.reachesServer else { return }
        for (id, pending) in stored(in: defaults) {
            guard library.views.contains(where: { $0.id == id }), !Browser.isWriting(id, in: library),
                  sending.insert(id).inserted else { continue }
            let title = library.views.first { $0.id == id }?.title
            let result = await library.changeView(id, pending.change, baseVersion: pending.baseVersion)
            sending.remove(id)
            switch result {
            case .success(let view):
                // A window may have kept a newer change meanwhile, which is its own to send.
                forget(pending, of: id, in: defaults)
                Browser.pendingChangeLanded(view, sent: pending.change, in: library)
            case .failure(let failure) where failure.kind == .offline:
                continue
            case .failure(let failure):
                // What the person changed goes to the clipboard before it is dropped, and the windows show the view.
                giveBack(pending.change, of: title, failure: failure, in: library)
                forget(pending, of: id, in: defaults)
                Browser.pendingChangeRefused(id, in: library)
            }
        }
    }

    /// Puts a refused change on the clipboard and says why, as every path that drops one does first.
    static func giveBack(_ change: LibraryViewChange, of title: String?, failure: ViewWriteFailure, in library: any ItemLibrary) {
        library.notices.notKept(
            String(localized: "View Not Saved"), text: text(of: change, view: title),
            reason: String(localized: "Marfa didn’t take a change to a view made while your server couldn’t be reached: \(failure.message)"))
    }

    /// The change in words the person can make it again from: the view, and each setting it replaces whole, as Marfa
    /// names it. Never empty.
    static func text(of change: LibraryViewChange, view title: String? = nil) -> String {
        var lines: [String] = []
        if let title { lines.append(String(localized: "View: \(title)")) }
        if let name = change.title { lines.append(String(localized: "Name: \(name)")) }
        if let query = change.query {
            let types = query.types.map(\.rawValue).joined(separator: ", ")
            lines.append(String(localized: "Types: \(types.isEmpty ? String(localized: "Any") : types)"))
            lines.append(String(localized: "From: \(ListScope(tier: query.tier).title)"))
            lines.append(String(localized: "Archived Items: \(ArchivedItems(states: query.states).title)"))
            lines.append(String(localized: "Filter: \(query.filter ?? String(localized: "None"))"))
            if let beneath = query.beneath { lines.append(String(localized: "Beneath: \(beneath.rawValue)")) }
        }
        if let sort = change.sort {
            let keys = sort.map { $0.field + ($0.ascending ? " ↑" : " ↓") }
            lines.append(String(localized: "Sort: \(keys.isEmpty ? String(localized: "None") : keys.joined(separator: ", "))"))
        }
        switch change.group {
        case .set(let group):
            var way = group.field
            if let bucket = group.bucket {
                way += " (\(bucket.rawValue))"
            } else if let other = group.otherBucket {
                way += " (\(other))"
            } else if group.byPresence {
                way += " (presence)"
            }
            lines.append(String(localized: "Group: \(way)"))
            if !group.order.isEmpty { lines.append(String(localized: "Group order: \(words(group.order))")) }
            if !group.hidden.isEmpty { lines.append(String(localized: "Hidden groups: \(words(group.hidden))")) }
        case .clear: lines.append(String(localized: "Group: None"))
        case nil: break
        }
        if lines.isEmpty { lines.append(String(localized: "A change to a view’s settings")) }
        return lines.joined(separator: "\n")
    }

    private static func words(_ keys: [JSONValue]) -> String {
        keys.map { key in
            switch key {
            case .null: "null"
            case .string(let text): text
            case .bool(let flag): flag ? "true" : "false"
            default: String(describing: key)
            }
        }.joined(separator: ", ")
    }
}
