import Foundation
import Observation

/// What came of a write to the stored settings.
nonisolated enum StoredSettingsWrite: Equatable, Sendable {
    case saved
    /// The settings were found changed on the server, or another Marfa answering at the address, so nothing was sent and
    /// the page shows what is there now.
    case elsewhere
    case failed(OwnerFailure)
}

/// The server's stored settings as a page last read them, and the one way a page changes them: a write is sent only after a
/// fresh read finds each setting it changes still as the page showed it, to the instance that was read, so a change made
/// elsewhere is told and never written over. Monitoring and Limits each hold one.
@Observable @MainActor final class StoredSettings {
    private let context: OwnerContext
    private let calls: any InstanceCalls

    private(set) var snapshot: InstanceSettingsSnapshot?
    private(set) var failure: OwnerFailure?
    private(set) var isLoading = false
    private(set) var isWriting = false

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
        guard let shown = snapshot, !isWriting else { return .failed(.failed(String(localized: "Wait for the last change to finish."))) }
        isWriting = true
        defer { isWriting = false }
        do throws(OwnerFailure) {
            let fresh = try await calls.storedSettings()
            if fresh.instanceID != shown.instanceID || changes.keys.contains(where: { Self.differs(shown.setting($0), fresh.setting($0)) }) {
                snapshot = fresh
                return .elsewhere
            }
            try await calls.change(changes, instanceID: shown.instanceID)
            snapshot = try? await calls.storedSettings()
            failure = nil
            return .saved
        } catch {
            await context.learn(from: error)
            if error == .conflict {
                snapshot = try? await calls.storedSettings()
                return .elsewhere
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
        case .conflict:
            String(localized: "This changed somewhere else, so MAPP read it again. Nothing was changed.")
        default:
            OwnerWording.line(failure)
        }
    }

    static let elsewhere = String(localized: "This changed somewhere else, so MAPP read it again. Nothing was changed.")

    private static func plain(_ text: String) -> Bool {
        !text.contains("`") && !text.contains("_") && !text.contains("/config") && !text.isEmpty
    }
}
