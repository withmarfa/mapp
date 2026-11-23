import Foundation
import Observation

/// What came of a write to the stored settings.
nonisolated enum StoredSettingsWrite: Equatable, Sendable {
    case saved
    /// These settings were found changed on the server since the page showed them, so nothing was sent and the page shows what
    /// is there now.
    case elsewhere([String])
    case failed(OwnerFailure)
}

/// The server's stored settings as a page last read them, and the one way a page changes them: a write is sent only after a
/// fresh read finds each setting it changes still as the page showed it, to the instance that was read, so a change made
/// elsewhere is told and never written over. A write that arrives while another runs waits for it. Another Marfa answering at
/// the address is told as that, and nothing of it is taken as what the page shows. Monitoring and Limits each hold one.
@Observable @MainActor final class StoredSettings {
    private let context: OwnerContext
    private let calls: any InstanceCalls

    private(set) var snapshot: InstanceSettingsSnapshot?
    private(set) var failure: OwnerFailure?
    private(set) var isLoading = false
    private(set) var isWriting = false
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []

    init(context: OwnerContext, calls: any InstanceCalls) {
        self.context = context
        self.calls = calls
    }

    func setting(_ key: String) -> StoredSetting? { snapshot?.setting(key) }

    /// Reads the settings. A page that already shows some keeps them while the answer comes.
    func load() async {
        guard !isLoading, !isWriting else { return }
        isLoading = true
        defer { isLoading = false }
        do throws(OwnerFailure) {
            snapshot = try await calls.storedSettings()
            failure = nil
        } catch {
            failure = error
            await context.learn(from: error)
        }
    }

    /// Sends `changes`, unless a setting they change is no longer as the page showed it.
    func write(_ changes: [String: StoredSettingChange]) async -> StoredSettingsWrite {
        while isWriting { await withCheckedContinuation { waiting.append($0) } }
        guard let shown = snapshot else { return .failed(.failed(String(localized: "The server’s answer couldn’t be read."))) }
        isWriting = true
        defer {
            isWriting = false
            let next = waiting
            waiting = []
            for waiter in next { waiter.resume() }
        }
        do throws(OwnerFailure) {
            let fresh = try await calls.storedSettings()
            if fresh.instanceID != shown.instanceID { return .failed(.instanceChanged) }
            let moved = changes.keys.filter { Self.differs(shown.setting($0), fresh.setting($0)) }
            if !moved.isEmpty {
                snapshot = fresh
                return .elsewhere(moved.sorted())
            }
            try await calls.change(changes, instanceID: shown.instanceID)
            // A read that fails now must not leave the values that were just sent unknown, or a later write of the same
            // value would find them "changed elsewhere".
            snapshot = (try? await calls.storedSettings()) ?? shown.applying(changes)
            failure = nil
            return .saved
        } catch {
            await context.learn(from: error)
            if error == .conflict {
                if let fresh = try? await calls.storedSettings(), fresh.instanceID == shown.instanceID { snapshot = fresh }
                return .elsewhere(changes.keys.sorted())
            }
            return .failed(error)
        }
    }

    private static func differs(_ shown: StoredSetting?, _ fresh: StoredSetting?) -> Bool {
        shown?.isSet != fresh?.isSet || shown?.value != fresh?.value
    }
}

/// What a refused change to a stored setting says, in one plain line. The server's own words are used only where they hold
/// no setting's name or code, which a person has no use for.
nonisolated enum StoredSettingWording {
    static func line(_ failure: OwnerFailure) -> String {
        switch failure {
        case .refused(let reason), .failed(let reason):
            plain(reason) ? reason : String(localized: "The server refused this change. Nothing was changed.")
        default:
            OwnerWording.line(failure)
        }
    }

    /// What is told when settings were found changed elsewhere, by the names the page gives them.
    static func elsewhere(_ names: [String]) -> String {
        let list = names.formatted(.list(type: .and))
        return names.count == 1
            ? String(localized: "\(list) was changed elsewhere. The app read the new value; yours wasn’t saved.")
            : String(localized: "\(list) were changed elsewhere. The app read the new values; yours weren’t saved.")
    }

    private static func plain(_ text: String) -> Bool {
        !text.contains("`") && !text.contains("_") && !text.contains("/config") && !text.isEmpty
    }
}
