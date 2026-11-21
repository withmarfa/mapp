import Foundation
import Marfa
import Observation

/// The Keys page: the owner's keys and the keys apps made. A key's access can only be narrowed, a key can be made to expire
/// sooner, and a new key is shown once. A key revoked elsewhere while its page is open is told as gone.
@Observable @MainActor final class KeysModel: OwnerDraftHolding {
    /// What the New Key sheet holds.
    struct Draft: Equatable {
        var name = ""
        var source = ""
        var expires: Expiry = .days(90)
        var tier: KeyTier = .feed
        var everyType: AccessLevel = .read
        /// Types given more or less than every type, by type or pattern.
        var exceptions: [String: AccessLevel] = [:]
        var permissions: Set<String> = []
    }

    enum Expiry: Hashable, Sendable {
        case never
        case days(Int)

        func date(from now: Date = .now, calendar: Calendar = .current) -> Date? {
            switch self {
            case .never: nil
            case .days(let days): calendar.date(byAdding: .day, value: days, to: now)
            }
        }
    }

    /// A change waiting on the owner's answer.
    struct Question: Identifiable, Equatable {
        enum Action: Equatable {
            case revoke(String)
            case expire(String, Date)
            case narrow(String, pattern: String, to: AccessLevel)
            case removePermission(String, from: String)
        }

        let id = UUID()
        let action: Action
        let title: String
        let message: String
        let confirm: String
    }

    enum Sheet: Equatable {
        case new
        case shown
        case rename(String)
    }

    private let context: OwnerContext

    private(set) var keys: [KeyInfo] = []
    private(set) var typeNames: [String: String] = [:]
    private(set) var failure: OwnerFailure?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var sheet: Sheet?
    var draft = Draft()
    /// Why the server refused the new key, in one line; the sheet keeps what was typed.
    private(set) var draftError: String?
    /// Why the source was refused, in one line under the Source field.
    private(set) var sourceError: String?
    private(set) var isMaking = false
    /// The key just made, shown once and dropped when the sheet closes.
    private(set) var created: CreatedKey?
    /// One line under a key's rows whose change was refused, by the key's id.
    private(set) var rowErrors: [String: String] = [:]
    /// The keys found gone while their page was open.
    private(set) var gone: Set<String> = []
    var question: Question?
    var renameDraft = ""
    private(set) var renameError: String?
    private(set) var revoked: String?

    init(context: OwnerContext) {
        self.context = context
    }

    func key(_ id: String) -> KeyInfo? { keys.first { $0.id == id } }

    var ownersKeys: [KeyInfo] { keys.filter { $0.appClientID == nil }.sorted(by: Self.byUse) }
    var appKeys: [KeyInfo] { keys.filter { $0.appClientID != nil }.sorted(by: Self.byUse) }

    private static func byUse(_ lhs: KeyInfo, _ rhs: KeyInfo) -> Bool {
        (lhs.lastUsed ?? .distantPast) > (rhs.lastUsed ?? .distantPast)
    }

    /// Whether MAPP may make a key, which is a different permission from listing and revoking them.
    var canMake: Bool { context.grants().contains(.keysMint) }

    /// The permissions MAPP may hand a new key: only what it holds itself.
    var givablePermissions: [String] {
        InstancePermission.allCases.filter { context.grants().contains($0) }.map(\.rawValue).sorted()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            let read = try await context.calls.keys()
            keys = read
            gone = gone.filter { id in !read.contains { $0.id == id } }
            failure = nil
        } catch {
            failure = error
            await context.learn(from: error)
            return
        }
        typeNames = (try? await context.calls.typeNames()) ?? typeNames
    }

    // MARK: New key

    func beginNewKey() {
        draft = Draft()
        draftError = nil
        sourceError = nil
        sheet = .new
    }

    /// The source is a short code stamped on what the key writes: lowercase words joined by hyphens.
    static func source(from name: String) -> String {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }
        return words.joined(separator: "-")
    }

    var canMakeDraft: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isMaking
    }

    func make() async {
        guard canMakeDraft else { return }
        isMaking = true
        defer { isMaking = false }
        draftError = nil
        sourceError = nil
        var types: [String: AccessLevel] = ["*": draft.everyType]
        for (pattern, level) in draft.exceptions { types[pattern] = level }
        let request = NewKey(
            label: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            source: draft.source.trimmingCharacters(in: .whitespacesAndNewlines), tier: draft.tier,
            expires: draft.expires.date(), types: types, permissions: draft.permissions.sorted())
        do {
            created = try await context.calls.create(request)
            sheet = .shown
            await load()
        } catch {
            if case .sourceHeld(let reason) = error { sourceError = reason } else { draftError = OwnerWording.line(error) }
            await context.learn(from: error)
        }
    }

    /// Closes the sheet; the plaintext key goes with it, as it is shown only once.
    func closeSheet() {
        guard !isMaking else { return }
        sheet = nil
        created = nil
        draftError = nil
        sourceError = nil
        renameError = nil
    }

    // MARK: A key

    func beginRename(_ key: KeyInfo) {
        renameDraft = key.label
        renameError = nil
        sheet = .rename(key.id)
    }

    var canRename: Bool { !renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func rename() async {
        guard case .rename(let id)? = sheet, canRename else { return }
        do {
            try await apply(id, KeyChange(label: renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)))
            sheet = nil
        } catch {
            renameError = OwnerWording.line(error)
        }
    }

    func setTier(_ tier: KeyTier, of key: KeyInfo) async {
        await change(key.id, KeyChange(tier: tier))
    }

    /// Asks before lowering what `pattern` may do for `key`. Only narrowing is asked, and a key cannot be widened again.
    func askToNarrow(_ key: KeyInfo, pattern: String, to level: AccessLevel) {
        guard let held = key.types[pattern], level < held else { return }
        let what = AccessScopes.title(of: pattern, names: typeNames)
        question = Question(
            action: .narrow(key.id, pattern: pattern, to: level), title: String(localized: "Narrow “\(key.label)”?"),
            message: String(localized: "\(what) goes from \(held.title) to \(level.title). This can’t be undone: a key’s access can’t be widened again, and anything using it loses what it no longer reaches."),
            confirm: String(localized: "Narrow"))
    }

    func askToRemove(permission: String, from key: KeyInfo) {
        guard key.permissions.contains(permission) else { return }
        let what = OwnerWording.title(of: permission)
        question = Question(
            action: .removePermission(key.id, from: permission), title: String(localized: "Remove “\(what)” from “\(key.label)”?"),
            message: String(localized: "“\(key.label)” can no longer do this. This can’t be undone: a permission can’t be given back to a key."),
            confirm: String(localized: "Remove"))
    }

    func askToExpire(_ key: KeyInfo, on date: Date) {
        if let expires = key.expires, date >= expires { return }
        question = Question(
            action: .expire(key.id, date), title: String(localized: "Make “\(key.label)” expire sooner?"),
            message: String(localized: "It stops working on \(OwnerWording.day(date)), and anything using it stops with it. Making a key last longer isn’t possible."),
            confirm: String(localized: "Make It Expire"))
    }

    func askToRevoke(_ key: KeyInfo) {
        question = Question(
            action: .revoke(key.id), title: String(localized: "Revoke “\(key.label)”?"),
            message: String(localized: "Anything using it stops at once. This can’t be undone."), confirm: String(localized: "Revoke"))
    }

    func cancelQuestion() { question = nil }

    func confirm(_ asked: Question) async {
        question = nil
        switch asked.action {
        case .expire(let id, let date):
            await change(id, KeyChange(expires: date))
        case .narrow(let id, let pattern, let level):
            guard let key = key(id), let held = key.types[pattern], level < held else { return }
            var types = key.types
            types[pattern] = level
            await change(id, KeyChange(types: types))
        case .removePermission(let id, let permission):
            guard let key = key(id) else { return }
            await change(id, KeyChange(permissions: key.permissions.filter { $0 != permission }))
        case .revoke(let id):
            rowErrors[id] = nil
            do {
                try await context.calls.revoke(id)
                keys.removeAll { $0.id == id }
                revoked = id
            } catch {
                if error == .notFound {
                    markGone(id)
                } else {
                    rowErrors[id] = OwnerWording.line(error)
                }
                await context.learn(from: error)
            }
        }
    }

    private func change(_ id: String, _ change: KeyChange) async {
        rowErrors[id] = nil
        do {
            try await apply(id, change)
        } catch {
            rowErrors[id] = OwnerWording.line(error)
        }
    }

    /// Sends a change and takes the key as the server answers it. A key that is gone is told so, and nothing else changes.
    private func apply(_ id: String, _ change: KeyChange) async throws(OwnerFailure) {
        do {
            let updated = try await context.calls.change(id, change)
            if let index = keys.firstIndex(where: { $0.id == id }) { keys[index] = updated }
        } catch {
            if error == .notFound { markGone(id) }
            await context.learn(from: error)
            throw error
        }
    }

    private func markGone(_ id: String) {
        gone.insert(id)
        keys.removeAll { $0.id == id }
    }

    func isGone(_ id: String) -> Bool { gone.contains(id) }

    // MARK: Closing

    /// What the New Key sheet holds, which the app gives back when Settings closes. A key already made is never handed back,
    /// as its secret is shown once and kept nowhere: the person is told it was made, and that it can be revoked.
    func takeDrafts() -> [OwnerDraft] {
        guard !isMaking else { return [] }
        defer {
            if sheet == .new || sheet == .shown { sheet = nil }
            created = nil
        }
        if sheet == .shown, let created {
            return [
                .told(
                    title: String(localized: "Key Not Copied"),
                    message: String(localized: "The key “\(created.label)” was made, and its secret can’t be shown again. If you didn’t copy it, revoke the key on the Keys page."))
            ]
        }
        guard sheet == .new else { return [] }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = draft.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || !source.isEmpty else { return [] }
        let lines = [
            name.isEmpty ? nil : String(localized: "Name: \(name)"),
            source.isEmpty ? nil : String(localized: "Source: \(source)"),
        ].compactMap { $0 }
        return [.typed(title: String(localized: "Key Not Made"), text: lines.joined(separator: "\n"))]
    }
}
