import Foundation

/// A setting of the Marfa server itself that the Marfa's pages read and change: its name, how long it keeps deleted items,
/// versions and logs, and how it keeps files. Only plain settings that take effect at once are here; the enforcement
/// levers and the settings that need a receiver set up by whoever runs the server are not.
nonisolated enum InstanceSetting: String, CaseIterable, Hashable, Sendable {
    case name
    case trashRetentionDays
    case versionRecentDays
    case versionDailyDays
    case versionWeeklyDays
    case versionMaxVersions
    case auditRetentionDays
    case eventLogRetentionDays
    case rowLogRetentionDays
    case inboundHandledRetentionDays
    case inboundPendingRetentionDays
    case blobMinCopies
    case diskReserveMegabytes
    case enrichmentEnabled
    case enrichmentOcrEnabled
    case mcpFetchEnabled
    case mcpFetchMaxMegabytes
    case blobCleanupEnabled
    case blobCleanupGraceSeconds

    /// Every name the contract allows is at most this many characters (Unicode scalars), after trimming.
    static let nameLimit = 200
    /// What a megabyte is for the two settings the server counts in bytes: the unit its own defaults (128 and 50) are whole in.
    static let bytesPerMegabyte = 1_048_576

    enum Kind: Hashable, Sendable { case text, count, flag }

    var kind: Kind {
        switch self {
        case .name: .text
        case .enrichmentEnabled, .enrichmentOcrEnabled, .mcpFetchEnabled, .blobCleanupEnabled: .flag
        default: .count
        }
    }

    var isNumber: Bool { kind == .count }

    /// The numbers the contract accepts, in the unit the page shows. A day count of 0 is allowed.
    var range: ClosedRange<Int> {
        switch self {
        case .name, .enrichmentEnabled, .enrichmentOcrEnabled, .mcpFetchEnabled, .blobCleanupEnabled: 0...0
        case .trashRetentionDays, .versionRecentDays, .versionDailyDays, .versionWeeklyDays, .auditRetentionDays, .eventLogRetentionDays,
            .rowLogRetentionDays, .inboundHandledRetentionDays, .inboundPendingRetentionDays:
            0...36500
        case .versionMaxVersions: 1...1_000_000
        case .blobMinCopies: 1...1_000_000
        case .diskReserveMegabytes: 0...(1_099_511_627_776 / Self.bytesPerMegabyte)
        case .mcpFetchMaxMegabytes: 1...(1_099_511_627_776 / Self.bytesPerMegabyte)
        case .blobCleanupGraceSeconds: 0...31_536_000
        }
    }

    /// What the server uses while the setting is unset and whoever runs it has set nothing else. A key cannot read the
    /// server's environment, so this is only the documented value, which the page says may differ. It is shown, never
    /// compared with: whether a change keeps things for less time is judged only against a value the server holds.
    var documentedDefault: Int? {
        switch self {
        case .name, .enrichmentEnabled, .enrichmentOcrEnabled, .mcpFetchEnabled, .blobCleanupEnabled: nil
        case .trashRetentionDays: 60
        case .versionRecentDays: 30
        case .versionDailyDays: 90
        case .versionWeeklyDays: 365
        case .versionMaxVersions: 500
        case .auditRetentionDays: 90
        case .eventLogRetentionDays: 30
        case .rowLogRetentionDays: 30
        case .inboundHandledRetentionDays: 7
        case .inboundPendingRetentionDays: 30
        case .blobMinCopies: 1
        case .diskReserveMegabytes: 128
        case .mcpFetchMaxMegabytes: 50
        case .blobCleanupGraceSeconds: 86_400
        }
    }

    /// The settings each page shows, in the order it shows them.
    static let versionSettings: [InstanceSetting] = [.versionRecentDays, .versionDailyDays, .versionWeeklyDays, .versionMaxVersions]
    static let logSettings: [InstanceSetting] = [
        .auditRetentionDays, .eventLogRetentionDays, .rowLogRetentionDays, .inboundHandledRetentionDays, .inboundPendingRetentionDays,
    ]
    static let fileSettings: [InstanceSetting] = [
        .blobMinCopies, .diskReserveMegabytes, .enrichmentEnabled, .enrichmentOcrEnabled, .mcpFetchEnabled, .mcpFetchMaxMegabytes,
        .blobCleanupEnabled, .blobCleanupGraceSeconds,
    ]

    /// The settings whose windows must not decrease, in order: recent, then daily, then weekly.
    static let versionWindows: [InstanceSetting] = [.versionRecentDays, .versionDailyDays, .versionWeeklyDays]

    var serverKey: String {
        switch self {
        case .name: "name"
        case .trashRetentionDays: "trash_retention_days"
        case .versionRecentDays: "version_recent_days"
        case .versionDailyDays: "version_daily_snapshot_days"
        case .versionWeeklyDays: "version_weekly_snapshot_days"
        case .versionMaxVersions: "version_max_versions"
        case .auditRetentionDays: "audit_retention_days"
        case .eventLogRetentionDays: "event_log_retention_days"
        case .rowLogRetentionDays: "row_log_retention_days"
        case .inboundHandledRetentionDays: "inbound_handled_retention_days"
        case .inboundPendingRetentionDays: "inbound_pending_retention_days"
        case .blobMinCopies: "blob_min_copies"
        case .diskReserveMegabytes: "disk_reserve_bytes"
        case .enrichmentEnabled: "enrichment_enabled"
        case .enrichmentOcrEnabled: "enrichment_ocr_enabled"
        case .mcpFetchEnabled: "mcp_fetch_enabled"
        case .mcpFetchMaxMegabytes: "mcp_fetch_max_bytes"
        case .blobCleanupEnabled: "blob_cleanup_enabled"
        case .blobCleanupGraceSeconds: "blob_cleanup_grace_seconds"
        }
    }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .trashRetentionDays: String(localized: "Delete from Trash After")
        case .versionRecentDays: String(localized: "Keep Every Version For")
        case .versionDailyDays: String(localized: "Then One a Day Up To")
        case .versionWeeklyDays: String(localized: "Then One a Week Up To")
        case .versionMaxVersions: String(localized: "Most Versions per Item")
        case .auditRetentionDays: String(localized: "Activity")
        case .eventLogRetentionDays: String(localized: "Events")
        case .rowLogRetentionDays: String(localized: "Table Changes")
        case .inboundHandledRetentionDays: String(localized: "Connector Deliveries, Handled")
        case .inboundPendingRetentionDays: String(localized: "Connector Deliveries, Waiting")
        case .blobMinCopies: String(localized: "Copies of Each File")
        case .diskReserveMegabytes: String(localized: "Keep Free on Disk")
        case .enrichmentEnabled: String(localized: "Read Text in Files")
        case .enrichmentOcrEnabled: String(localized: "Read Text in Pictures")
        case .mcpFetchEnabled: String(localized: "Let Agents Fetch Files")
        case .mcpFetchMaxMegabytes: String(localized: "Largest File")
        case .blobCleanupEnabled: String(localized: "Remove Unused Files")
        case .blobCleanupGraceSeconds: String(localized: "Remove After")
        }
    }

    /// Whether a shorter value removes something that cannot be recovered, so the person agrees to it first.
    var isRetention: Bool {
        switch self {
        case .blobCleanupGraceSeconds, .trashRetentionDays, .versionRecentDays, .versionDailyDays, .versionWeeklyDays, .versionMaxVersions, .auditRetentionDays,
            .eventLogRetentionDays, .rowLogRetentionDays, .inboundHandledRetentionDays, .inboundPendingRetentionDays:
            true
        default: false
        }
    }

    /// Whether 0 keeps things with no age limit, so it is the furthest a setting can reach.
    var zeroMeansNoLimit: Bool {
        switch self {
        case .trashRetentionDays, .auditRetentionDays, .eventLogRetentionDays, .rowLogRetentionDays, .inboundHandledRetentionDays,
            .inboundPendingRetentionDays:
            true
        default: false
        }
    }

    /// The value that keeps things for the least time, which no other value can undercut. Zero days with no limit keeps
    /// things with no age limit, so its least is a day.
    var shortestKept: Int { zeroMeansNoLimit ? 1 : range.lowerBound }

    /// Whether `value` is so long that nothing a server could be set to keeps more: no limit where zero means it, and the
    /// largest the contract takes for every other setting.
    func isUnlimited(_ value: Int) -> Bool {
        (zeroMeansNoLimit && value == 0) || value >= range.upperBound
    }

    /// Whether `value` reaches further than `other` in what it keeps. Zero where it means no limit is the furthest; a zero
    /// version window is empty, so it is the least.
    func keepsLonger(_ value: Int, than other: Int) -> Bool {
        if zeroMeansNoLimit {
            if value == 0 { return other != 0 }
            if other == 0 { return false }
        }
        return value > other
    }
}

nonisolated enum InstanceValue: Hashable, Sendable {
    case text(String)
    case number(Int)
    case flag(Bool)
}

/// The settings a server has set. A setting it has not set is absent, which means its default applies.
nonisolated struct InstanceConfig: Hashable, Sendable {
    var values: [InstanceSetting: InstanceValue] = [:]
    /// Which instance answered, as `GET /config` gives it.
    var instanceID: String?
    var signInAddress: String?

    func number(_ setting: InstanceSetting) -> Int? {
        if case .number(let number)? = values[setting] { return number }
        return nil
    }

    func flag(_ setting: InstanceSetting) -> Bool? {
        if case .flag(let flag)? = values[setting] { return flag }
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
        case .flag(let flag)?: flag ? "true" : "false"
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
        if kind == .flag {
            switch trimmed {
            case "true": return .value(.flag(true))
            case "false": return .value(.flag(false))
            default: return .unset
            }
        }
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
    /// the app’s sign-in lacks `config.manage`.
    case notPermitted
    /// Another instance answers at the address than the one the settings were read from.
    case instanceChanged
    /// There is no server to ask for settings: none is set, or the library has none, as the sample does not.
    case unsupported
    case keyRefused
    /// The server refused the values; the message is its reason.
    case refused(String)
    case failed(String)

    /// What every page says when another Marfa answers at the address.
    static let anotherMarfaSentence = String(localized: "Another Marfa now answers at this address. Nothing was sent.")

    var message: String {
        switch self {
        case .unreachable:
            String(localized: "The app can’t reach the server. If its address starts with http://, macOS may be refusing it. Your items and changes aren’t affected.")
        case .notPermitted:
            String(localized: "The app’s sign-in isn’t allowed to change this server’s settings. Ask whoever runs the server to allow it, or use the server’s console.")
        case .instanceChanged:
            Self.anotherMarfaSentence + " " + String(localized: "These are its settings, not the ones you were editing.")
        case .unsupported:
            OwnerWording.line(.unsupported)
        case .keyRefused:
            String(localized: "The server has ended the app’s sign-in. Sign in again in Connection.")
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
