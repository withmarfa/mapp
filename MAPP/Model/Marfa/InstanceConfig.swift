import Foundation

/// A setting of the Marfa server itself that This Marfa lets the person read and change: its name, how long deleted
/// items stay, and how long it keeps the versions of an item. Only plain settings that take effect at once are
/// here; the enforcement levers and the settings that need a receiver set up by whoever runs the server are not.
nonisolated enum InstanceSetting: String, CaseIterable, Hashable, Sendable {
    case name
    case trashRetentionDays
    case versionRecentDays
    case versionDailyDays
    case versionWeeklyDays
    case versionMaxVersions

    /// Every name the contract allows is at most this many characters (Unicode scalars), after trimming.
    static let nameLimit = 200

    var isNumber: Bool { self != .name }

    /// The numbers the contract accepts. A day count of 0 is allowed, and a version count must be at least 1.
    var range: ClosedRange<Int> {
        switch self {
        case .name: 0...0
        case .trashRetentionDays, .versionRecentDays, .versionDailyDays, .versionWeeklyDays: 0...36500
        case .versionMaxVersions: 1...9_007_199_254_740_991
        }
    }

    /// What the server uses while the setting is unset and whoever runs it has set nothing else. A key cannot read the
    /// server's environment, so this is only the documented value, which the page says may differ. It is shown, never
    /// compared with: whether a change keeps things for less time is judged only against a value the server holds.
    var documentedDefault: Int? {
        switch self {
        case .name: nil
        case .trashRetentionDays: 60
        case .versionRecentDays: 30
        case .versionDailyDays: 90
        case .versionWeeklyDays: 365
        case .versionMaxVersions: 500
        }
    }

    /// The settings whose windows must not decrease, in order: recent, then daily, then weekly.
    static let versionWindows: [InstanceSetting] = [.versionRecentDays, .versionDailyDays, .versionWeeklyDays]

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .trashRetentionDays: String(localized: "Deleted items kept for")
        case .versionRecentDays: String(localized: "All versions kept for")
        case .versionDailyDays: String(localized: "One version a day kept for")
        case .versionWeeklyDays: String(localized: "One version a week kept for")
        case .versionMaxVersions: String(localized: "Most versions kept per item")
        }
    }

    /// The value that keeps things for the least time, which no other value can undercut. Zero days of trash keeps
    /// deleted items with no age limit, so its least is a day.
    var shortestKept: Int { self == .trashRetentionDays ? 1 : range.lowerBound }

    /// Whether `value` is so long that nothing a server could be set to keeps more: no limit for trash, and the
    /// largest the contract takes for every other setting.
    func isUnlimited(_ value: Int) -> Bool {
        (self == .trashRetentionDays && value == 0) || value >= range.upperBound
    }

    /// Whether `value` reaches further than `other` in what it keeps. Zero days of trash keeps deleted items with no
    /// age limit, so it is the furthest; a zero version window is empty, so it is the least.
    func keepsLonger(_ value: Int, than other: Int) -> Bool {
        if self == .trashRetentionDays {
            if value == 0 { return other != 0 }
            if other == 0 { return false }
        }
        return value > other
    }
}

nonisolated enum InstanceValue: Hashable, Sendable {
    case text(String)
    case number(Int)
}

/// The settings a server has set. A setting it has not set is absent, which means its default applies.
nonisolated struct InstanceConfig: Hashable, Sendable {
    var values: [InstanceSetting: InstanceValue] = [:]
    /// Which instance answered, as `GET /config` gives it.
    var instanceID: String?

    func number(_ setting: InstanceSetting) -> Int? {
        if case .number(let number)? = values[setting] { return number }
        return nil
    }

    var name: String? {
        if case .text(let text)? = values[.name] { return text }
        return nil
    }

    /// The text a field shows for `setting`: empty where it is unset.
    func text(_ setting: InstanceSetting) -> String {
        switch values[setting] {
        case .text(let text)?: text
        case .number(let number)?: String(number)
        case nil: ""
        }
    }
}

/// Exactly what a change sends: the settings to set and the settings to remove, so their defaults apply.
nonisolated struct InstanceConfigPatch: Hashable, Sendable {
    var values: [InstanceSetting: InstanceValue] = [:]
    var clear: Set<InstanceSetting> = []

    var isEmpty: Bool { values.isEmpty && clear.isEmpty }
    var settings: Set<InstanceSetting> { Set(values.keys).union(clear) }
}

/// Why what was typed for a setting can't be sent. Each is checked before anything is sent.
nonisolated enum InstanceSettingProblem: Hashable, Sendable {
    case notWhole
    case outOfRange(ClosedRange<Int>)
    case nameTooLong
    case nameHidden
    /// A version window shorter than the one before it.
    case shorterThan(InstanceSetting)

    var message: String {
        switch self {
        case .notWhole:
            String(localized: "Use digits only.")
        case .outOfRange(let range):
            String(localized: "Use a number from \(range.lowerBound) to \(range.upperBound).")
        case .nameTooLong:
            String(localized: "Use \(InstanceSetting.nameLimit) characters or fewer.")
        case .nameHidden:
            String(localized: "Remove control and text-direction characters.")
        case .shorterThan(let earlier):
            String(localized: "Can’t be shorter than “\(earlier.title)”.")
        }
    }
}

/// What typed text means for a setting.
nonisolated enum InstanceEntry: Hashable, Sendable {
    /// Empty: the setting is removed, so its default applies.
    case unset
    case value(InstanceValue)
    case invalid(InstanceSettingProblem)
}

nonisolated extension InstanceSetting {
    /// Reads what was typed, by the contract's rules: a whole number inside the range, or a name of 1 to 200
    /// characters with no control or text-direction characters, checked before it is trimmed as the server does.
    func entry(from text: String) -> InstanceEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNumber {
            guard !trimmed.isEmpty else { return .unset }
            guard trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return .invalid(.notWhole) }
            guard let number = Int(trimmed), range.contains(number) else { return .invalid(.outOfRange(range)) }
            return .value(.number(number))
        }
        guard text.unicodeScalars.allSatisfy({ !Self.isHidden($0) }) else { return .invalid(.nameHidden) }
        guard !trimmed.isEmpty else { return .unset }
        guard trimmed.unicodeScalars.count <= Self.nameLimit else { return .invalid(.nameTooLong) }
        return .value(.text(trimmed))
    }

    private static func isHidden(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control || scalar.properties.isBidiControl
    }
}

/// Why the server's settings could not be read or changed, in terms the page can word for a person.
nonisolated enum InstanceConfigFailure: Error, Hashable, Sendable {
    case unreachable
    /// The key MAPP uses lacks `config.manage`.
    case notPermitted
    /// Another instance answers at the address than the one the settings were read from.
    case instanceChanged
    case keyRefused
    /// The server refused the values; the message is its reason.
    case refused(String)
    case failed(String)

    var message: String {
        switch self {
        case .unreachable:
            String(localized: "MAPP can’t reach the server. If its address starts with http://, macOS may be refusing it. Your notes and changes aren’t affected.")
        case .notPermitted:
            String(localized: "The key MAPP uses isn’t allowed to change this server’s settings. Ask whoever runs the server to allow it, or use the server’s console.")
        case .instanceChanged:
            String(localized: "Another Marfa now answers at this address. Nothing was sent, and these are its settings, not the ones you were editing.")
        case .keyRefused:
            String(localized: "The server didn’t accept MAPP’s key. Choose a new key in Library.")
        case .refused(let reason), .failed(let reason):
            reason
        }
    }
}

/// Where a server's settings come from. Both calls are requests to the server, so they can fail while the rest of
/// the library works.
nonisolated protocol InstanceConfigSource: Sendable {
    func read() async throws(InstanceConfigFailure) -> InstanceConfig
    /// Sends exactly `patch` and gives back the whole configuration as the server now has it. `instanceID` is the
    /// instance the settings were read from: if another instance answers, the server writes nothing and the call
    /// throws `instanceChanged`.
    func update(_ patch: InstanceConfigPatch, expecting instanceID: String?) async throws(InstanceConfigFailure) -> InstanceConfig
}
