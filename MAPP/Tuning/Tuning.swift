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
    /// Add a knob here to show it in the panel; remove it here when it is settled. Today it holds the `Chips` group,
    /// which adjusts `ChipLooks`: when a chip value is settled, delete its knob and keep its named default there.
    ///
    /// To add one: declare it with `Knob.slider`, `.toggle` or `.picker`, with the code's own constant as its
    /// default, and list it here. Read it in the view with `number(_:)`, `choice(_:as:)` or, for a toggle,
    /// `tuning[knob] == .flag(true)`, behind `#if DEBUG` with the constant in the `#else`, so Release keeps the
    /// constant. The `Copy` button turns the values into text to paste into a chat. Settle a knob by deleting its
    /// declaration, its use and this entry in one change; none stays as a setting. Panel text is not localized.
    static let shared = Tuning(knobs: Chips.fields.map(\.knob))

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

extension Tuning {
    /// The `Chips` group: each knob adjusts one number of `ChipLooks`, with that value's default as its start.
    enum Chips {
        typealias Field = (knob: Knob, path: WritableKeyPath<ChipLooks, Double>)

        private static func size(_ name: String, _ path: WritableKeyPath<ChipLooks, Double>, in range: ClosedRange<Double>, step: Double = 1) -> Field {
            (.slider("Chips", name, ChipLooks.defaults[keyPath: path], in: range, step: step), path)
        }

        private static func opacity(_ name: String, _ path: WritableKeyPath<ChipLooks, Double>) -> Field {
            (.slider("Chips", name, ChipLooks.defaults[keyPath: path], in: 0...1, step: 0.005), path)
        }

        static let fields: [Field] = [
            size("Height", \.height, in: 16...32),
            size("Corner radius", \.cornerRadius, in: 0...16, step: 0.5),
            size("Text size", \.textSize, in: 9...16, step: 0.5),
            size("Padding", \.padding, in: 0...16, step: 0.5),
            size("Gap", \.gap, in: 0...12, step: 0.5),
            size("Type chip mark", \.chipMarkSize, in: 8...20),
            size("Person circle", \.personCircle, in: 10...26),
            size("Person initials", \.personInitialsSize, in: 6...12, step: 0.5),
            opacity("Type tint", \.typeTintOpacity),
            opacity("Type tint dark", \.typeTintOpacityDark),
            opacity("Mark tint", \.markOpacity),
            opacity("Icon depth", \.inkDepth),
            opacity("Icon depth dark", \.inkDepthDark),
            opacity("Icon ceiling dark", \.inkCeilingDark),
            size("Status edge width", \.statusEdgeWidth, in: 0...2, step: 0.25),
            opacity("Edge light", \.edgeOpacityLight),
            opacity("Edge dark", \.edgeOpacityDark),
            opacity("Option fill light", \.optionFillOpacityLight),
            opacity("Option fill dark", \.optionFillOpacityDark),
            opacity("Tag fill light", \.tagFillOpacityLight),
            opacity("Tag fill dark", \.tagFillOpacityDark),
            opacity("Status fill dark", \.statusDarkFillOpacity),
            opacity("Filter fill light", \.filterFillOpacityLight),
            opacity("Filter fill dark", \.filterFillOpacityDark),
            opacity("Chevron", \.chevronOpacity),
        ]
    }

    /// The chip looks with every knob's value applied. A view that reads it in its `body` redraws when a knob moves.
    var chipLooks: ChipLooks {
        var looks = ChipLooks.defaults
        for field in Chips.fields { looks[keyPath: field.path] = number(field.knob) }
        return looks
    }
}
#endif
