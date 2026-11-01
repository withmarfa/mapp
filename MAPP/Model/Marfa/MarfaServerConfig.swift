import Foundation
import Marfa

/// Reads and changes the Marfa server's own settings (`GET` and `PATCH /config`), which need the `config.manage`
/// permission. It uses the same address and key as the working copy, read from the key store on each call, and
/// calls the package's generated client over `URLSession`, so App Transport Security applies as it does to
/// `MarfaServerVersions`.
nonisolated struct MarfaServerConfig: InstanceConfigSource {
    let connection: MarfaConnection
    let keys: any KeyStore
    /// How long a call waits for the server before it fails, so an unreachable server never leaves the page waiting.
    var timeout = Duration.seconds(20)

    @concurrent func read() async throws(InstanceConfigFailure) -> InstanceConfig {
        let server = try server()
        do {
            return Self.config(try await server.config(timeout: timeout))
        } catch {
            throw Self.failure(error)
        }
    }

    @concurrent func update(_ patch: InstanceConfigPatch, expecting instanceID: String?) async throws(InstanceConfigFailure) -> InstanceConfig {
        let server = try server()
        do {
            return Self.config(try await server.updateConfig(Self.patch(patch), expecting: instanceID, timeout: timeout))
        } catch {
            throw Self.failure(error)
        }
    }

    private func server() throws(InstanceConfigFailure) -> Server {
        let stored: String?
        do { stored = try keys.key(for: connection.address) } catch { throw .failed(Words.keyUnreadable) }
        guard let key = stored, !key.isEmpty else { throw .keyRefused }
        return connection.server(key: key)
    }

    static func config(_ answer: Marfa.InstanceConfig) -> InstanceConfig {
        var config = InstanceConfig()
        config.instanceID = answer.instanceID
        config.values[.name] = answer.name.map { .text($0) }
        config.values[.trashRetentionDays] = answer.trashRetentionDays.map { .number($0) }
        config.values[.versionRecentDays] = answer.versionRecentDays.map { .number($0) }
        config.values[.versionDailyDays] = answer.versionDailySnapshotDays.map { .number($0) }
        config.values[.versionWeeklyDays] = answer.versionWeeklySnapshotDays.map { .number($0) }
        config.values[.versionMaxVersions] = answer.versionMaxVersions.map { .number($0) }
        return config
    }

    /// A change that names only the settings in `patch`: a field left out stays as it is, and a cleared one is removed.
    static func patch(_ patch: InstanceConfigPatch) -> Marfa.InstanceConfigPatch {
        func number(_ setting: InstanceSetting) -> SettingChange<Int>? {
            if patch.clear.contains(setting) { return .clear }
            if case .number(let number)? = patch.values[setting] { return .set(number) }
            return nil
        }
        var change = Marfa.InstanceConfigPatch()
        if patch.clear.contains(.name) {
            change.name = .clear
        } else if case .text(let text)? = patch.values[.name] {
            change.name = .set(text)
        }
        change.trashRetentionDays = number(.trashRetentionDays)
        change.versionRecentDays = number(.versionRecentDays)
        change.versionDailySnapshotDays = number(.versionDailyDays)
        change.versionWeeklySnapshotDays = number(.versionWeeklyDays)
        change.versionMaxVersions = number(.versionMaxVersions)
        return change
    }

    /// The server's sentence without the raw details the client appends to it.
    static func reason(_ message: String) -> String {
        message.components(separatedBy: " Details:").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? message
    }

    static func failure(_ error: any Error) -> InstanceConfigFailure {
        guard let error = error as? MarfaError else { return .failed(error.localizedDescription) }
        if error.isOffline { return .unreachable }
        if error.isKeyRefusal { return .keyRefused }
        switch error {
        case .forbidden: return .notPermitted
        case .validation(_, let message): return .refused(reason(message))
        case .instanceChanged: return .instanceChanged
        default: return .failed(error.message)
        }
    }
}
