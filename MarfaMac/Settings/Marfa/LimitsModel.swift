import Foundation
import Observation

/// What a limit is counted in. A size is held by the server in bytes and shown in megabytes (1 MB is 1,048,576 bytes).
nonisolated enum LimitUnit: Hashable, Sendable {
    case megabytes, requests, seconds, characters, times, deliveries, viewers

    static let bytesPerMegabyte = 1_048_576.0

    var title: String {
        switch self {
        case .megabytes: String(localized: "MB")
        case .requests: String(localized: "requests")
        case .seconds: String(localized: "seconds")
        case .characters: String(localized: "characters")
        case .times: String(localized: "times")
        case .deliveries: String(localized: "deliveries")
        case .viewers: String(localized: "viewers")
        }
    }

    /// The number a person reads for what the server holds.
    func shown(_ held: Int) -> Double {
        self == .megabytes ? Double(held) / Self.bytesPerMegabyte : Double(held)
    }
}

/// A limit the server lets the owner change, with the range it accepts. The range is the contract's, in what the server
/// holds, so a value outside it is refused here before anything is sent.
nonisolated struct LimitSetting: Identifiable, Hashable, Sendable {
    let key: String
    let title: String
    let unit: LimitUnit
    let range: ClosedRange<Int>
    var line: String?
    /// The switch the limit depends on: while it is off the limit does nothing, so the field is off too.
    var requires: String?

    var id: String { key }

    /// The text a field shows for `held`: a whole number where it is one, otherwise up to two decimals, grouped and pointed as
    /// the Mac's region does.
    func text(for held: Int, locale: Locale = .current) -> String {
        unit.shown(held).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    enum Entry: Equatable, Sendable {
        /// Nothing typed: the stored value is removed so the server's default applies.
        case useDefault
        case value(Int)
        case invalid(String)
    }

    /// Reads what was typed as a number the server accepts, grouped and pointed as the Mac's region writes one: the field's own
    /// text can be typed back, and a separator that is neither the region's grouping nor its point is refused, never guessed at.
    func entry(from text: String, locale: Locale = .current) -> Entry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .useDefault }
        guard let number = Self.number(trimmed, locale: locale) else { return .invalid(String(localized: "Use digits only.")) }
        if unit != .megabytes, number != number.rounded() { return .invalid(String(localized: "Use a whole number."))}
        let held = unit == .megabytes ? number * LimitUnit.bytesPerMegabyte : number
        guard held <= Double(range.upperBound), held >= Double(range.lowerBound) else { return .invalid(rangeLine) }
        return .value(unit == .megabytes ? Int(held.rounded()) : Int(number))
    }

    private static func number(_ text: String, locale: Locale) -> Double? {
        let point = locale.decimalSeparator ?? "."
        let group = locale.groupingSeparator ?? ","
        var typed = text
        // A region that groups with a space (or a narrow or no-break one) accepts any of them.
        if group.allSatisfy(\.isWhitespace) { typed = String(typed.map { $0.isWhitespace ? Character(group) : $0 }) }
        let digits = "[0-9]"
        let fraction = "(\(NSRegularExpression.escapedPattern(for: point))\(digits)+)?"
        let plain = "^\(digits)+\(fraction)$"
        let grouped = "^\(digits){1,3}(\(NSRegularExpression.escapedPattern(for: group))\(digits){3})+\(fraction)$"
        guard typed.range(of: plain, options: .regularExpression) != nil || typed.range(of: grouped, options: .regularExpression) != nil
        else { return nil }
        let normalized = typed.replacingOccurrences(of: group, with: "").replacingOccurrences(of: point, with: ".")
        guard let number = Double(normalized), number.isFinite else { return nil }
        return number
    }

    /// "Use a number from 1 to 32 MB." Where the least is a single byte, it is "above 0".
    var rangeLine: String {
        let most = text(for: range.upperBound)
        let unit = unit.title
        if self.unit == .megabytes, range.lowerBound <= 1 {
            return String(localized: "Use a number above 0, up to \(most) \(unit).")
        }
        return String(localized: "Use a number from \(text(for: range.lowerBound)) to \(most) \(unit).")
    }

    private static func bytes(_ key: String, _ title: String, _ most: Int, line: String? = nil, requires: String? = nil) -> LimitSetting {
        LimitSetting(key: key, title: title, unit: .megabytes, range: 1...most, line: line, requires: requires)
    }

    private static let tebibyte = 1_099_511_627_776

    static let largestRequest = bytes("max_request_bytes", String(localized: "Largest Request"), tebibyte)
    static let largestBulkRequest = bytes(
        "max_bulk_request_bytes", String(localized: "Largest Bulk Request"), 33_554_432)
    static let requestsPerWindow = LimitSetting(
        key: "rate_limit_requests", title: String(localized: "Requests from Each App or Key"), unit: .requests, range: 1...1_000_000, requires: rateLimitSwitch)
    static let keyRequestsPerWindow = LimitSetting(
        key: "rate_limit_keys_requests", title: String(localized: "Requests That Manage Keys"), unit: .requests, range: 1...1_000_000, requires: rateLimitSwitch)
    static let window = LimitSetting(
        key: "rate_limit_window_seconds", title: String(localized: "Window"), unit: .seconds, range: 1...86_400, requires: rateLimitSwitch)
    static let largestFileRead = bytes("enrichment_max_blob_bytes", String(localized: "Largest File Read"), tebibyte)
    static let mostTextKept = LimitSetting(
        key: "enrichment_max_text_chars", title: String(localized: "Most Text Kept"), unit: .characters, range: 1...100_000_000)
    static let tries = LimitSetting(key: "enrichment_max_attempts", title: String(localized: "Tries"), unit: .times, range: 1...100)
    static let largestDelivery = bytes("inbound_max_bytes", String(localized: "Largest Delivery"), tebibyte)
    static let deliveriesPerWindow = LimitSetting(
        key: "rate_limit_inbound_requests", title: String(localized: "Requests per Window"), unit: .requests, range: 1...1_000_000,
        requires: rateLimitSwitch)
    static let waiting = LimitSetting(
        key: "inbound_backlog_deliveries", title: String(localized: "Waiting, at Most"), unit: .deliveries, range: 1...1_000_000)
    static let mostViewers = LimitSetting(
        key: "event_stream_max_viewers", title: String(localized: "Most Viewers at Once"), unit: .viewers, range: 0...1_000_000)
    static let largestFetch = bytes("mcp_fetch_max_bytes", String(localized: "Largest File"), tebibyte, requires: fetchSwitch)
    static let fetchTime = LimitSetting(
        key: "mcp_fetch_timeout_seconds", title: String(localized: "Time Allowed"), unit: .seconds, range: 1...3_600, requires: fetchSwitch)

    static let rateLimitSwitch = "rate_limit_enabled"
    static let fetchSwitch = "mcp_fetch_enabled"

    static let limitFields = [largestRequest, largestBulkRequest, window, requestsPerWindow, keyRequestsPerWindow, largestDelivery, deliveriesPerWindow, waiting, mostViewers]
    static let storageFields = [largestFileRead, mostTextKept, tries, largestFetch, fetchTime]
    static let all = limitFields + storageFields
}

/// Sends changed limits on Return or when the field loses focus. A failed write restores the last value the server reported.
@Observable @MainActor final class LimitsModel: OwnerDraftHolding {
    private let store: StoredSettings

    /// What each field being edited holds; a field with no entry shows what the server holds.
    var drafts: [String: String] = [:]
    /// One line under a limit's title after a change that was not made.
    private(set) var lines: [String: String] = [:]
    /// What was told after a change found changed elsewhere; it closes when the person next edits, or is closed.
    private(set) var notice: String?
    private(set) var saving: Set<String> = []

    init(store: StoredSettings) {
        self.store = store
    }

    convenience init(context: OwnerContext, calls: any InstanceCalls) {
        self.init(store: StoredSettings(context: context, calls: calls))
    }

    var failure: OwnerFailure? { store.failure }
    var isLoaded: Bool { store.snapshot != nil && store.failure == nil }

    func setting(_ key: String) -> StoredSetting? { store.setting(key) }

    func load() async {
        await store.load()
    }

    // MARK: Reading

    var startUp: [StartUpSetting] { store.snapshot?.startUp ?? [] }

    func held(_ limit: LimitSetting) -> Int? { store.setting(limit.key)?.value?.int }

    /// What the field shows: what was typed, else what the server holds.
    func text(_ limit: LimitSetting) -> String {
        drafts[limit.key] ?? held(limit).map { limit.text(for: $0) } ?? ""
    }

    func isOn(_ key: String) -> Bool { store.setting(key)?.value?.bool ?? false }

    /// Whether the field takes a value: not while the switch the limit depends on is off.
    func isEnabled(_ limit: LimitSetting) -> Bool { limit.requires.map(isOn) ?? true }

    /// What is wrong with what was typed, before it is sent: the line to show under the title.
    func line(_ limit: LimitSetting) -> String? {
        if let draft = drafts[limit.key], case .invalid(let line) = limit.entry(from: draft) { return line }
        return lines[limit.key]
    }

    func hasProblem(_ limit: LimitSetting) -> Bool { line(limit) != nil }

    // MARK: Changing

    /// Sends a typed value that differs from what the server holds. An invalid one is kept where it was typed.
    func commit(_ limit: LimitSetting) async {
        guard held(limit) != nil, let typed = drafts[limit.key], !saving.contains(limit.key) else { return }
        let change: StoredSettingChange
        switch limit.entry(from: typed) {
        case .invalid: return
        case .useDefault:
            guard store.setting(limit.key)?.isStored == true else {
                drafts[limit.key] = nil
                return
            }
            change = .clear
        case .value(let value):
            guard value != held(limit) else {
                drafts[limit.key] = nil
                lines[limit.key] = nil
                return
            }
            change = .set(.int(value))
        }
        await send([limit.key: change], keys: [limit.key])
    }

    /// Takes what is typed in a field; the notice about an earlier change closes.
    func type(_ text: String, for limit: LimitSetting) {
        drafts[limit.key] = text
        notice = nil
    }

    func dismissNotice() { notice = nil }

    func setSwitch(_ key: String, _ on: Bool) async {
        guard store.setting(key)?.value?.bool != nil, !saving.contains(key), isOn(key) != on else { return }
        await send([key: .set(.bool(on))], keys: [key])
    }

    private func send(_ changes: [String: StoredSettingChange], keys: [String]) async {
        saving.formUnion(keys)
        defer { saving.subtract(keys) }
        notice = nil
        for key in keys { lines[key] = nil }
        switch await store.write(changes) {
        case .saved:
            for key in keys { drafts[key] = nil }
        case .elsewhere(let moved):
            for key in keys { drafts[key] = nil }
            notice = StoredSettingWording.elsewhere(moved.map(Self.name))
        case .failed(let failure):
            for key in keys {
                drafts[key] = nil
                lines[key] = StoredSettingWording.line(failure)
            }
        }
    }

    private static func name(_ key: String) -> String {
        if key == LimitSetting.rateLimitSwitch { return String(localized: "Limit Requests") }
        if key == LimitSetting.fetchSwitch { return String(localized: "Let Tools Fetch Files") }
        return LimitSetting.all.first { $0.key == key }?.title ?? key
    }

    // MARK: Drafts

    /// Typed values that were not sent, handed back when Settings closes.
    func takeDrafts() -> [OwnerDraft] {
        let held = drafts
        drafts = [:]
        return LimitSetting.all.compactMap { limit in
            guard let text = held[limit.key]?.trimmingCharacters(in: .whitespaces), !text.isEmpty, limit.entry(from: text) != .value(self.held(limit) ?? -1)
            else { return nil }
            return .typed(title: limit.title, text: text)
        }
    }
}
