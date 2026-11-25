import Foundation

/// The changes to saved views that could not reach the server, kept on this Mac until it can. A window keeps the change
/// it holds for a view here as it makes it offline, so leaving the view, closing the window or quitting loses nothing,
/// and a write that lands takes it away. Once the server can be reached, `send(in:defaults:)` writes each change no open
/// window is about to write itself, whatever the windows show.
///
/// A change is sent on the version of the view it was made on, so the server merges it with what another app changed
/// meanwhile, or refuses it where they changed the same setting (`views/change-conflict`). A change the server refuses
/// is given back on the clipboard (`Notices.notKept`), in words the person can make it again from.
@MainActor
enum PendingViewChanges {
    nonisolated struct Pending: Codable, Hashable, Sendable {
        var change: LibraryViewChange
        var baseVersion: Int64
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

    static func keep(_ change: LibraryViewChange, baseVersion: Int64, for id: ItemID, in defaults: UserDefaults) {
        update(in: defaults) { $0[id] = change.isEmpty ? nil : Pending(change: change, baseVersion: baseVersion) }
    }

    static func forget(_ id: ItemID, in defaults: UserDefaults) {
        guard stored(in: defaults)[id] != nil else { return }
        update(in: defaults) { $0[id] = nil }
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
            let result = await library.changeView(id, pending.change, baseVersion: pending.baseVersion)
            sending.remove(id)
            switch result {
            case .success(let view):
                // A window may have kept a newer change meanwhile, which is its own to send.
                if stored(in: defaults)[id] == pending { forget(id, in: defaults) }
                Browser.pendingChangeLanded(view, sent: pending.change, in: library)
            case .failure(let failure) where failure.kind == .offline:
                continue
            case .failure(let failure):
                forget(id, in: defaults)
                // The library has said why; what the person changed goes to the clipboard, and the windows show the view.
                library.notices.notKept(
                    String(localized: "View Not Saved"), text: text(of: pending.change),
                    reason: String(localized: "Marfa didn’t take a change to a view made while your server couldn’t be reached: \(failure.message)"))
                Browser.pendingChangeRefused(id, in: library)
            }
        }
    }

    /// The change in words the person can make it again from: each setting it replaces, as Marfa names it.
    static func text(of change: LibraryViewChange) -> String {
        var lines: [String] = []
        if let title = change.title { lines.append(String(localized: "Name: \(title)")) }
        if let query = change.query {
            if !query.types.isEmpty { lines.append(String(localized: "Types: \(query.types.map(\.rawValue).joined(separator: ", "))")) }
            if let filter = query.filter { lines.append(String(localized: "Filter: \(filter)")) }
        }
        if let sort = change.sort {
            let keys = sort.map { $0.field + ($0.ascending ? " ↑" : " ↓") }
            lines.append(String(localized: "Sort: \(keys.isEmpty ? String(localized: "None") : keys.joined(separator: ", "))"))
        }
        switch change.group {
        case .set(let group): lines.append(String(localized: "Group: \(group.field)"))
        case .clear: lines.append(String(localized: "Group: None"))
        case nil: break
        }
        return lines.joined(separator: "\n")
    }
}
