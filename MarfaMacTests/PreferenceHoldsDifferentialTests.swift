import Foundation
import Testing
@testable import MarfaMac

/// Generated traces of store set-asides, the person's changes through the stores, other Macs' changes (back to an earlier
/// value among them), another build, Import, an import cut off before the sync heard of it, and Reset. Each runs twice:
/// once as the app runs, and once with every entry removed as soon as it is written, which is the sync without holds.
/// At each step every row write of the first run is one the second makes, with the same value, so a hold only ever
/// leaves out a deletion; and this Mac's values are the same in both, but where a held row did not take another Mac's
/// change back to its value at the hold (the second residual).
@MainActor @Suite(.hangLimit) final class PreferenceHoldsDifferentialTests {
    static let library = "marfa:https://one"
    static let types = ["core.note", "core.task"]
    static let places: [PlaceView] = [.library, .feed, .favorites]

    static func look(_ type: String) -> PreferenceUnit { .row(.types, setting: "look", key: type) }
    static func density(_ place: PlaceView) -> PreferenceUnit { .row(.places, setting: "placeDensity", key: place.storageKey) }
    static let date = PreferenceUnit.member(.general, DateFormat.key)

    static let start: PreferenceUnits = [
        look("core.note"): #"{"date":"created"}"#, look("core.task"): #"{"date":"edited"}"#,
        density(.library): #""compact""#, density(.feed): #""standard""#, density(.favorites): #""compact""#,
        date: #""relative""#,
    ]

    enum Step: CustomStringConvertible {
        /// The stored look becomes one this build cannot read, and the store reads it.
        case damageLook(String)
        /// The stored look gains a member this build does not know, and the store reads it.
        case extendLook(String)
        case changeLook(String, LookDate)
        case restoreLook(String)
        /// The stored density becomes a word this build does not know, which a person's write then drops.
        case damageDensity(PlaceView)
        case changeDensity(PlaceView, Density?)
        /// The stored date format is a word this build does not know, and the date store reads it.
        case damageDate
        case otherMac(PreferenceUnit, String?)
        case anotherBuild
        case importLook(String, LookDate)
        /// An import wrote a look and the app stopped before the sync heard of it; the next launch reads it.
        case cutOffImport(String, LookDate)
        case reset

        var description: String {
            switch self {
            case .damageLook(let type): "damageLook(\(type))"
            case .extendLook(let type): "extendLook(\(type))"
            case .changeLook(let type, let date): "changeLook(\(type), \(date))"
            case .restoreLook(let type): "restoreLook(\(type))"
            case .damageDensity(let place): "damageDensity(\(place.storageKey))"
            case .changeDensity(let place, let density): "changeDensity(\(place.storageKey), \(density?.rawValue ?? "nil"))"
            case .damageDate: "damageDate"
            case .otherMac(let unit, let value): "otherMac(\(unit), \(value ?? "nil"))"
            case .anotherBuild: "anotherBuild"
            case .importLook(let type, let date): "importLook(\(type), \(date))"
            case .cutOffImport(let type, let date): "cutOffImport(\(type), \(date))"
            case .reset: "reset"
            }
        }
    }

    /// A small, fixed generator, so a failing trace can be run again by its seed.
    struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }

        mutating func pick<Element>(_ elements: [Element]) -> Element { elements[Int(next() % UInt64(elements.count))] }
    }

    static func trace(seed: Int, length: Int) -> [Step] {
        var generator = Generator(state: UInt64(seed))
        let dates: [LookDate] = [.created, .edited, .occurred]
        var fresh = 0
        return (0..<length).map { _ in
            fresh += 1
            switch generator.next() % 16 {
            case 0, 1, 2: return .damageLook(generator.pick(types))
            case 3: return .extendLook(generator.pick(types))
            case 4, 5: return .changeLook(generator.pick(types), generator.pick(dates))
            case 6: return .restoreLook(generator.pick(types))
            case 7: return .damageDensity(generator.pick(places))
            case 8: return .changeDensity(generator.pick(places), generator.pick([Density.standard, .compact, nil]))
            case 9: return .damageDate
            case 10, 11:
                let unit = look(generator.pick(types))
                // Back to where it started, which a held row may hold, as well as new values and a removal.
                let values: [String?] = [start[unit], #"{"date":"created","n":\#(fresh)}"#, #"{"date":"later\#(fresh)"}"#, nil]
                return .otherMac(unit, generator.pick(values))
            case 12:
                let unit = density(generator.pick(places))
                return .otherMac(unit, generator.pick([start[unit], #""later\#(fresh)""#, nil]))
            case 13: return generator.next().isMultiple(of: 2) ? .anotherBuild : .reset
            case 14: return .cutOffImport(generator.pick(types), generator.pick(dates))
            default: return .importLook(generator.pick(types), generator.pick(dates))
            }
        }
    }

    /// One Mac's run of a trace, alone with its own Marfa.
    final class Run {
        let holds: Bool
        let defaults: ThrowawayDefaults
        let points: RestorePoints
        let copy = FakePreferencesCopy()
        let looks: TypeLooks
        var sync: PreferencesSync?
        var item = ""
        var builds = 0

        init(holds: Bool) {
            self.holds = holds
            defaults = ThrowawayDefaults.make("MarfaMacTests.PreferenceHoldsDifferential.\(holds)")
            points = RestorePoints(folder: URL.temporaryDirectory.appending(path: "PreferenceHoldsDifferential-\(UUID().uuidString)"))
            looks = TypeLooks(defaults: defaults)
        }

        deinit {
            try? FileManager.default.removeItem(at: points.folder)
        }

        /// In the run without holds, removes each entry as soon as it is written.
        func dropReports() {
            if !holds { defaults.removeObject(forKey: PreferenceHolds.key) }
        }

        func attach(build: String) async {
            let sync = PreferencesSync(
                defaults: defaults, domain: defaults.suite, enabled: true, coalescing: .milliseconds(10), build: build,
                restorePoints: points, reload: { [weak self] in
                    self?.looks.reload()
                    self?.dropReports()
                })
            sync.attach(copy, library: PreferenceHoldsDifferentialTests.library, name: { nil })
            self.sync = sync
            await sync.flush()
        }

        func start() async {
            defaults.set("relative", forKey: DateFormat.key)
            item = await copy.add(PreferenceHoldsDifferentialTests.start)
            await attach(build: PreferencesSync.appBuild)
        }

        func flush() async {
            for _ in 0..<3 { await sync?.flush() }
        }

        var local: PreferenceUnits {
            var units: PreferenceUnits = [:]
            for setting in PreferencesMap.synced {
                if case .units(let held) = setting.read(defaults, library: PreferenceHoldsDifferentialTests.library) {
                    units.merge(held) { a, _ in a }
                }
            }
            return units
        }

        var marfa: PreferenceUnits {
            get async { await copy.unitsHeld(item) }
        }

        var held: Set<PreferenceUnit> { PreferencesSync.Record.read(defaults).marfas["instance-1"]?.held ?? [] }

        var rowsWritten: Int {
            get async { await copy.rowsWritten.count }
        }

        func rowsWritten(since count: Int) async -> [String] {
            await copy.rowsWritten.dropFirst(count).map { "\($0.id)=\($0.value ?? "deleted")" }
        }

        private func storedLooks() -> [String: Any] {
            defaults.data(forKey: TypeLooks.defaultsKey)
                .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        }

        private func setLook(_ type: String, _ look: Any) {
            var libraries = storedLooks()
            var looks = libraries[PreferenceHoldsDifferentialTests.library] as? [String: Any] ?? [:]
            looks[type] = look
            libraries[PreferenceHoldsDifferentialTests.library] = looks
            defaults.set(try? JSONSerialization.data(withJSONObject: libraries, options: .sortedKeys), forKey: TypeLooks.defaultsKey)
        }

        private static func text(_ date: LookDate) -> String {
            date == .occurred ? #"{"date":"occurred"}"# : date == .edited ? #"{"date":"edited"}"# : #"{"date":"created"}"#
        }

        func take(_ step: Step) async throws {
            switch step {
            case .damageLook(let type):
                setLook(type, ["date": "bogus"])
                looks.reload()
            case .extendLook(let type):
                setLook(type, ["date": "created", "glow": true])
                looks.reload()
            case .changeLook(let type, let date):
                looks.change(TypeID(type), in: PreferenceHoldsDifferentialTests.library, catalogue: LookFixture.catalogue()) { $0.date = date }
            case .restoreLook(let type):
                looks.restore(TypeID(type), in: PreferenceHoldsDifferentialTests.library)
            case .damageDensity(let place):
                var stored = defaults.data(forKey: PlaceDensities.key)
                    .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
                stored[place.storageKey] = "spacious"
                defaults.set(try? JSONSerialization.data(withJSONObject: stored, options: .sortedKeys), forKey: PlaceDensities.key)
                PlaceDensities.update(in: defaults) { $0.set(.compact, for: place == .library ? .feed : .library) }
            case .changeDensity(let place, let density):
                PlaceDensities.update(in: defaults) { $0.set(density, for: place) }
            case .damageDate:
                defaults.set("relative", forKey: DateFormat.key)
                DateFormat.setAsideUnreadable(in: defaults)
            case .otherMac(let unit, let value):
                if let value { await copy.change(item, [unit: value]) } else { await copy.change(item, [:], removing: [unit]) }
            case .anotherBuild:
                sync?.detach()
                builds += 1
                await attach(build: "next-\(builds)")
            case .importLook(let type, let date):
                let unit = PreferenceHoldsDifferentialTests.look(type)
                let units = [unit: Self.text(date)]
                _ = try await sync?.importSettings(SettingsFile(units: units, build: "", date: .now), sections: [SettingsFile.Section(unit)])
            case .cutOffImport(let type, let date):
                sync?.detach()
                setLook(type, ["date": "\(date)"])
                looks.reload()
                dropReports()
                builds += 1
                await attach(build: "next-\(builds)")
            case .reset:
                MacSettings.reset(in: defaults)
                sync?.replaced(PreferencesMap.synced)
            }
            dropReports()
        }
    }

    @Test(arguments: 1...24)
    func aHoldOnlyEverLeavesOutADeletion(seed: Int) async throws {
        let steps = Self.trace(seed: seed, length: 12)
        let held = Run(holds: true)
        let plain = Run(holds: false)
        await held.start()
        await plain.start()
        for (index, step) in steps.enumerated() {
            let context = "seed \(seed), step \(index): \(step), trace \(steps)"
            let heldBefore = await held.rowsWritten
            let plainBefore = await plain.rowsWritten
            try await held.take(step)
            try await plain.take(step)
            await held.flush()
            await plain.flush()
            let heldWrites = await held.rowsWritten(since: heldBefore)
            let plainWrites = Set(await plain.rowsWritten(since: plainBefore))
            for write in heldWrites {
                #expect(plainWrites.contains(write), "\(write) was written only with holds; \(context)")
            }
            let heldLocal = held.local
            let plainLocal = plain.local
            let heldMarfa = await held.marfa
            for unit in Set(heldLocal.keys).union(plainLocal.keys) where heldLocal[unit] != plainLocal[unit] {
                // The second residual: a held row that did not take a change back to its value at the hold.
                let residual = held.held.contains(unit) && heldLocal[unit] == nil && plainLocal[unit] == heldMarfa[unit]
                #expect(residual, "\(unit) differs here: \(heldLocal[unit] ?? "absent") against \(plainLocal[unit] ?? "absent"); \(context)")
            }
        }
    }

    /// The traces reach holds at all: without this, the property above would hold of any generator.
    @Test func theTracesHoldRows() async throws {
        var differences = 0
        for seed in 1...24 {
            let steps = Self.trace(seed: seed, length: 12)
            let held = Run(holds: true)
            let plain = Run(holds: false)
            await held.start()
            await plain.start()
            for step in steps {
                try await held.take(step)
                try await plain.take(step)
                await held.flush()
                await plain.flush()
                if await held.marfa != plain.marfa {
                    differences += 1
                    break
                }
            }
        }
        #expect(differences > 6)
    }
}
