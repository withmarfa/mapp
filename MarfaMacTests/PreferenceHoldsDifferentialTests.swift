import Foundation
import Testing
@testable import MarfaMac

/// Generated traces of store set-asides, the person's changes through the stores, another Mac's changes, another build,
/// Import and Reset, each run twice: once as the app runs, and once with every report removed as soon as it is written,
/// which leaves the decisions of the sync without the stores' reports. A report can only stop a unit being sent, so at
/// each step the first run never leaves the Marfa holding a value the second does not, and every value the person set
/// that the second run sent or kept is sent or kept by the first.
@MainActor @Suite(.hangLimit) final class PreferenceHoldsDifferentialTests {
    static let library = "marfa:https://one"
    static let types = ["core.note", "core.task"]
    static let places: [PlaceView] = [.library, .feed, .favorites]

    static func look(_ type: String) -> PreferenceUnit { .row(.types, setting: "look", key: type) }
    static func density(_ place: PlaceView) -> PreferenceUnit { .row(.places, setting: "placeDensity", key: place.storageKey) }

    static let start: PreferenceUnits = [
        look("core.note"): #"{"date":"created"}"#, look("core.task"): #"{"date":"edited"}"#,
        density(.library): #""compact""#, density(.feed): #""standard""#, density(.favorites): #""compact""#,
    ]

    enum Step: CustomStringConvertible {
        /// The stored look becomes one this build cannot read, and the store reads it.
        case damageLook(String)
        /// The stored look gains a member this build does not know, and the store reads it.
        case extendLook(String)
        case changeLook(String, LookDate)
        case restoreLook(String)
        /// The stored density becomes a word this build does not know.
        case damageDensity(PlaceView)
        case changeDensity(PlaceView, Density?)
        case resetView(PlaceView)
        case otherMac(PreferenceUnit, String?)
        case anotherBuild
        case importLook(String, LookDate)
        case reset

        var description: String {
            switch self {
            case .damageLook(let type): "damageLook(\(type))"
            case .extendLook(let type): "extendLook(\(type))"
            case .changeLook(let type, let date): "changeLook(\(type), \(date))"
            case .restoreLook(let type): "restoreLook(\(type))"
            case .damageDensity(let place): "damageDensity(\(place.storageKey))"
            case .changeDensity(let place, let density): "changeDensity(\(place.storageKey), \(density?.rawValue ?? "nil"))"
            case .resetView(let place): "resetView(\(place.storageKey))"
            case .otherMac(let unit, let value): "otherMac(\(unit), \(value ?? "nil"))"
            case .anotherBuild: "anotherBuild"
            case .importLook(let type, let date): "importLook(\(type), \(date))"
            case .reset: "reset"
            }
        }

        /// Whether the step is the person's own change through a store.
        var unitThePersonSets: PreferenceUnit? {
            switch self {
            case .changeLook(let type, _), .restoreLook(let type): PreferenceHoldsDifferentialTests.look(type)
            case .changeDensity(let place, _), .resetView(let place): PreferenceHoldsDifferentialTests.density(place)
            default: nil
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
            switch generator.next() % 14 {
            case 0, 1: return .damageLook(generator.pick(types))
            case 2: return .extendLook(generator.pick(types))
            case 3, 4: return .changeLook(generator.pick(types), generator.pick(dates))
            case 5: return .restoreLook(generator.pick(types))
            case 6: return .damageDensity(generator.pick(places))
            case 7, 8: return .changeDensity(generator.pick(places), generator.pick([Density.standard, .compact, nil]))
            case 9: return .resetView(generator.pick(places))
            case 10:
                let values: [String?] = [#"{"date":"created","n":\#(fresh)}"#, #"{"date":"later\#(fresh)"}"#, nil]
                return .otherMac(look(generator.pick(types)), generator.pick(values))
            case 11:
                return .otherMac(density(generator.pick(places)), generator.pick([#""later\#(fresh)""#, nil]))
            case 12: return generator.next().isMultiple(of: 2) ? .anotherBuild : .reset
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

        /// In the run without reports, removes each report as soon as it is written.
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
            case .changeDensity(let place, let density):
                PlaceDensities.update(in: defaults) { $0.set(density, for: place) }
            case .resetView(let place):
                PlaceDensities.update(in: defaults, addressing: [place.storageKey]) { $0.set(nil, for: place) }
            case .otherMac(let unit, let value):
                if let value { await copy.change(item, [unit: value]) } else { await copy.change(item, [:], removing: [unit]) }
            case .anotherBuild:
                sync?.detach()
                builds += 1
                await attach(build: "next-\(builds)")
            case .importLook(let type, let date):
                let value = date == .occurred ? #"{"date":"occurred"}"# : date == .edited ? #"{"date":"edited"}"# : #"{"date":"created"}"#
                let unit = PreferenceHoldsDifferentialTests.look(type)
                _ = try await sync?.importSettings(SettingsFile(units: [unit: value], build: "", date: .now), sections: [SettingsFile.Section(unit)])
                looks.reload()
            case .reset:
                MacSettings.reset(in: defaults)
                sync?.replaced(PreferencesMap.synced)
                looks.reload()
            }
            dropReports()
        }
    }

    @Test(arguments: 1...16)
    func aReportOnlyEverSendsLess(seed: Int) async throws {
        let steps = Self.trace(seed: seed, length: 10)
        let held = Run(holds: true)
        let plain = Run(holds: false)
        await held.start()
        await plain.start()
        for (index, step) in steps.enumerated() {
            let context = "seed \(seed), step \(index): \(step), trace \(steps)"
            var expected = await held.marfa
            if case .otherMac(let unit, let value) = step { expected[unit] = value }
            try await held.take(step)
            try await plain.take(step)
            await held.flush()
            await plain.flush()
            let heldMarfa = await held.marfa
            let plainMarfa = await plain.marfa
            for unit in Set(heldMarfa.keys).union(expected.keys) where heldMarfa[unit] != expected[unit] {
                #expect(plainMarfa[unit] == heldMarfa[unit], "\(unit) was sent only with reports; \(context)")
            }
            if let unit = step.unitThePersonSets, let value = plain.local[unit] ?? plainMarfa[unit],
               plain.local[unit] == value || plainMarfa[unit] == value
            {
                #expect(held.local[unit] == value || heldMarfa[unit] == value, "the person's \(unit) was lost; \(context)")
            }
        }
    }

    /// The traces reach holds at all: without this, the property above would hold of any generator.
    @Test func theTracesHoldRows() async throws {
        var differences = 0
        for seed in 1...16 {
            let steps = Self.trace(seed: seed, length: 10)
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
        #expect(differences > 3)
    }
}
