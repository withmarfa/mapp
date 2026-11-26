import Foundation
import Observation

/// What each server's person leaves out of search, kept in the defaults. A server is named as a library is
/// (`Libraries.libraryKey`), so two servers that share a type identifier keep their own. The connected server's entry syncs
/// through its Marfa (`PreferencesMap`).
///
/// Stored text that cannot be read, such as one a later version wrote, is moved aside under a key of its own, kept and
/// never removed; the servers whose entry can be read keep it, and the rest leave nothing out.
@Observable @MainActor
final class SearchLeaveOuts {
    static let defaultsKey = "searchLeaveOuts"
    /// Each entry is stored data that could not be read, in the order it was found.
    static let setAsideKey = "searchLeaveOutsSetAside"

    @ObservationIgnored private let defaults: UserDefaults
    private var held: [String: SearchLeaveOut]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        held = [:]
        reload()
    }

    /// Reads the stored value again, as when another Mac's change has reached the defaults (`PreferencesSync`).
    func reload() {
        guard let saved = defaults.data(forKey: Self.defaultsKey) else {
            held = [:]
            return
        }
        let (readable, unreadable) = Self.read(saved)
        held = readable
        guard let unreadable else { return }
        defaults.set((defaults.array(forKey: Self.setAsideKey) as? [Data] ?? []) + [unreadable], forKey: Self.setAsideKey)
        save()
        PreferenceHolds.recordByLibrary(unreadable, of: Self.defaultsKey, from: saved, in: defaults)
    }

    /// The entries that can be read, and the stored data of those that cannot: the whole of it where it is not an object
    /// of servers at all, otherwise an object of the unreadable entries alone.
    private static func read(_ saved: Data) -> (readable: [String: SearchLeaveOut], unreadable: Data?) {
        if let all = try? JSONDecoder().decode([String: SearchLeaveOut].self, from: saved) { return (all, nil) }
        guard let entries = (try? JSONSerialization.jsonObject(with: saved)) as? [String: Any] else { return ([:], saved) }
        var readable: [String: SearchLeaveOut] = [:]
        var unreadable: [String: Any] = [:]
        for (library, entry) in entries {
            if let data = try? JSONSerialization.data(withJSONObject: entry, options: .fragmentsAllowed),
               let leaveOut = try? JSONDecoder().decode(SearchLeaveOut.self, from: data) {
                readable[library] = leaveOut
            } else {
                unreadable[library] = entry
            }
        }
        let kept = (try? JSONSerialization.data(withJSONObject: unreadable, options: .sortedKeys)) ?? saved
        return (readable, kept)
    }

    /// What `library` leaves out of search; nothing until the person chooses.
    func leaveOut(for library: String) -> SearchLeaveOut { held[library] ?? SearchLeaveOut() }

    func update(_ library: String, _ change: (inout SearchLeaveOut) -> Void) {
        var leaveOut = leaveOut(for: library)
        change(&leaveOut)
        guard leaveOut != self.leaveOut(for: library) else { return }
        // An empty choice is the default, so it takes no space.
        held[library] = leaveOut.isEmpty ? nil : leaveOut
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(held) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
