import Foundation

extension PreferencesSync {
    /// What this Mac knows of each Marfa it adopted, and which it followed last.
    nonisolated struct Record: Codable, Equatable, Sendable {
        struct Adopted: Codable, Equatable, Sendable {
            var item: String
            var base: PreferenceUnits
            /// The field writes this Mac queued whose answer it has not taken, by the queued write's id.
            var awaiting: [String: Awaiting] = [:]
            /// How many field writes this Mac has queued, which orders them.
            var writes = 0
            /// The settings a store dropped or changed when it read what was written (`apply`), and what it left.
            var frozen: [PreferenceUnit: Frozen] = [:]
            /// The app that judged `frozen`; another tries those settings again.
            var frozenBuild: String?
            /// Set once this Mac removed the item or saw it in the bin, so an emptied bin does not bring it back.
            var removed: Bool?

            init(item: String, base: PreferenceUnits, frozenBuild: String? = nil) {
                self.item = item
                self.base = base
                self.frozenBuild = frozenBuild
            }
        }

        /// A field write waiting for its answer: the members it carried that this Mac changed.
        struct Awaiting: Codable, Equatable, Sendable {
            /// The opened copy that queued it (`PreferencesCopy.run`).
            var run: String
            var order: Int
            var members: PreferenceUnits
        }

        /// What the store left of a setting it could not read: nothing, or the part it could.
        struct Frozen: Codable, Equatable, Sendable {
            var left: String?
        }

        var marfas: [String: Adopted] = [:]
        var last: String?
        /// The Marfas whose settings were started again, whose next item is made from this Mac's settings.
        var restarting: Set<String> = []

        static func read(_ defaults: UserDefaults) -> Record {
            defaults.data(forKey: PreferencesSync.recordKey).flatMap { try? JSONDecoder().decode(Record.self, from: $0) } ?? Record()
        }

        /// Writes only a change, since every write to the defaults asks for another step.
        func save(_ defaults: UserDefaults) {
            guard self != Record.read(defaults), let data = try? JSONEncoder().encode(self) else { return }
            defaults.set(data, forKey: PreferencesSync.recordKey)
        }
    }
}
