#if DEBUG
import Foundation
import SwiftUI
import Testing

@testable import MAPP

struct TuningTests {
    private enum Shape: String, CaseIterable { case round, square }

    private let strength = Knob.slider("band", "strength", 0.6, in: 0...1, step: 0.05)
    private let enabled = Knob.toggle("band", "enabled", true)
    private let shape = Knob.picker("shapes", "shape", Shape.round)

    /// A registry on defaults of its own, so a test never reads or writes the app's.
    private func tuning(_ body: (Tuning, UserDefaults) throws -> Void) throws {
        let suite = "TuningTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(Tuning(knobs: [strength, enabled, shape], defaults: defaults), defaults)
    }

    @Test func aKnobStartsAtItsDefault() throws {
        try tuning { tuning, _ in
            #expect(tuning.number(strength) == 0.6)
            #expect(tuning[enabled] == .flag(true))
            #expect(tuning.choice(shape, as: Shape.self) == .round)
        }
    }

    @Test func aSetValueIsReadBackAndKeptForTheNextRun() throws {
        try tuning { tuning, defaults in
            tuning[strength] = .number(0.25)
            tuning[shape] = .option("square")
            #expect(tuning.number(strength) == 0.25)
            #expect(tuning.choice(shape, as: Shape.self) == .square)
            let later = Tuning(knobs: tuning.knobs, defaults: defaults)
            #expect(later.number(strength) == 0.25)
            #expect(later.choice(shape, as: Shape.self) == .square)
        }
    }

    @Test func aValueOutsideTheKnobIsClampedOrIgnored() throws {
        try tuning { tuning, defaults in
            tuning[strength] = .number(7)
            #expect(tuning.number(strength) == 1)
            tuning[strength] = .number(-1)
            #expect(tuning.number(strength) == 0)
            tuning[strength] = .number(.nan)
            #expect(tuning.number(strength) == 0.6)
            tuning[shape] = .option("triangle")
            #expect(tuning.choice(shape, as: Shape.self) == .round)
            defaults.set(99.0, forKey: Tuning.prefix + strength.id)
            #expect(Tuning(knobs: tuning.knobs, defaults: defaults).number(strength) == 1)
        }
    }

    @Test func resetReturnsEveryKnobToItsDefaultAndForgetsTheStoredValue() throws {
        try tuning { tuning, defaults in
            tuning[strength] = .number(0.1)
            tuning[enabled] = .flag(false)
            tuning[shape] = .option("square")
            tuning.reset()
            #expect(tuning.number(strength) == 0.6)
            #expect(tuning[enabled] == .flag(true))
            #expect(tuning.choice(shape, as: Shape.self) == .round)
            #expect(defaults.object(forKey: Tuning.prefix + strength.id) == nil)
        }
    }

    @Test func theReportNamesTheBuildThenListsEachKnobOnItsOwnLine() throws {
        try tuning { tuning, _ in
            tuning[strength] = .number(0.35)
            #expect(tuning.report(build: "19") == """
                MAPP build 19
                band.strength = 0.35
                band.enabled = true
                shapes.shape = round
                """)
        }
    }

    @Test func theAppsKnobsAreUniqueAndStartAtValuesTheyAccept() {
        let ids = Tuning.shared.knobs.map(\.id)
        #expect(Set(ids).count == ids.count)
        for knob in Tuning.shared.knobs { #expect(knob.coerced(knob.initial) == knob.initial, "\(knob.id)") }
    }

    @Test func onlyTheBandLeavesTheListsEdgeToTheApp() {
        #expect(ToolbarBand.ListEdge.band.systemStyle == nil)
        for edge in ToolbarBand.ListEdge.allCases where edge != .band { #expect(edge.systemStyle != nil) }
        #expect(ToolbarBand.WindowToolbarBackground.hidden.visibility == .hidden)
        #expect(ToolbarBand.WindowToolbarBackground.automatic.visibility == .automatic)
    }
}
#endif
