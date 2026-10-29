#if DEBUG
import Foundation
import Observation

/// Design values to adjust live in a Debug build and read back as text. A knob is a stopgap: delete it, and the
/// code that reads it, in the same change that settles its value. Nothing here is compiled into Release.
struct Knob: Identifiable {
    enum Kind {
        case slider(ClosedRange<Double>, step: Double)
        case toggle
        case picker([String])
    }

    enum Value: Equatable {
        case number(Double)
        case flag(Bool)
        case option(String)
    }

    let group: String
    let name: String
    let kind: Kind
    let initial: Value

    var id: String { group + "." + name }

    static func slider(_ group: String, _ name: String, _ initial: Double, in range: ClosedRange<Double>, step: Double) -> Knob {
        Knob(group: group, name: name, kind: .slider(range, step: step), initial: .number(initial))
    }

    static func toggle(_ group: String, _ name: String, _ initial: Bool) -> Knob {
        Knob(group: group, name: name, kind: .toggle, initial: .flag(initial))
    }

    static func picker<Choice: CaseIterable & RawRepresentable>(_ group: String, _ name: String, _ initial: Choice) -> Knob
    where Choice.RawValue == String {
        Knob(group: group, name: name, kind: .picker(Choice.allCases.map(\.rawValue)), initial: .option(initial.rawValue))
    }

    /// The value as a knob can hold it: a number inside the range, a choice that exists, and the initial value for
    /// anything of another kind.
    func coerced(_ value: Value) -> Value {
        switch (kind, value) {
        case (.slider(let range, _), .number(let number)):
            .number(number.isFinite ? min(max(number, range.lowerBound), range.upperBound) : initial.number ?? range.lowerBound)
        case (.toggle, .flag): value
        case (.picker(let options), .option(let option)): options.contains(option) ? value : initial
        default: initial
        }
    }
}

extension Knob.Value {
    var number: Double? { if case .number(let number) = self { number } else { nil } }

    /// How the value reads in the copied text.
    var text: String {
        switch self {
        case .number(let number): String(format: "%g", number)
        case .flag(let flag): String(flag)
        case .option(let option): option
        }
    }
}

/// Every knob's current value, kept in this build's defaults under `tuning.`. A view that reads a value in its
/// `body` redraws when it changes.
@Observable
final class Tuning {
    /// Add a knob here to show it in the panel; remove it here when it is settled. Empty until a design value needs
    /// comparing.
    static let shared = Tuning(knobs: [])

    static let prefix = "tuning."

    let knobs: [Knob]
    @ObservationIgnored private let defaults: UserDefaults
    private var values: [String: Knob.Value] = [:]

    init(knobs: [Knob], defaults: UserDefaults = .standard) {
        self.knobs = knobs
        self.defaults = defaults
        for knob in knobs { values[knob.id] = Self.stored(knob, in: defaults) }
    }

    subscript(knob: Knob) -> Knob.Value {
        get { values[knob.id] ?? knob.initial }
        set {
            let value = knob.coerced(newValue)
            values[knob.id] = value
            defaults.set(Self.object(value), forKey: Self.prefix + knob.id)
        }
    }

    func number(_ knob: Knob) -> Double { self[knob].number ?? 0 }

    func choice<Choice: RawRepresentable>(_ knob: Knob, as _: Choice.Type) -> Choice? where Choice.RawValue == String {
        if case .option(let option) = self[knob] { Choice(rawValue: option) } else { nil }
    }

    func reset() {
        for knob in knobs {
            defaults.removeObject(forKey: Self.prefix + knob.id)
            values[knob.id] = knob.initial
        }
    }

    /// The text to paste into a chat: the build, then one `group.name = value` per line.
    func report(build: String) -> String {
        (["MAPP build \(build)"] + knobs.map { "\($0.id) = \(self[$0].text)" }).joined(separator: "\n")
    }

    private static func object(_ value: Knob.Value) -> Any {
        switch value {
        case .number(let number): number
        case .flag(let flag): flag
        case .option(let option): option
        }
    }

    private static func stored(_ knob: Knob, in defaults: UserDefaults) -> Knob.Value {
        let raw = defaults.object(forKey: prefix + knob.id)
        let value: Knob.Value? = switch knob.initial {
        case .number: (raw as? Double).map(Knob.Value.number)
        case .flag: (raw as? Bool).map(Knob.Value.flag)
        case .option: (raw as? String).map(Knob.Value.option)
        }
        return value.map(knob.coerced) ?? knob.initial
    }
}
#endif
