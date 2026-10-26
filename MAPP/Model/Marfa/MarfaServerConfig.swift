import Foundation
import Marfa
import MarfaAPI

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
        let client = try client()
        do {
            return Self.config(try await client.getConfig().ok.body.json)
        } catch {
            throw Self.failure(error)
        }
    }

    @concurrent func update(_ patch: InstanceConfigPatch) async throws(InstanceConfigFailure) -> InstanceConfig {
        let client = try client()
        do {
            let answer = try await client.updateConfig(body: .json(Self.payload(patch)))
            return Self.config(try answer.ok.body.json)
        } catch {
            throw Self.failure(error)
        }
    }

    private func client() throws(InstanceConfigFailure) -> Client {
        guard let key = try? keys.key(for: connection), !key.isEmpty else { throw .keyRefused }
        return Client(connection.server(key: key), timeout: timeout)
    }

    static func config(_ answer: Components.Schemas.InstanceConfig) -> InstanceConfig {
        var config = InstanceConfig()
        config.values[.name] = answer.name.map { .text($0) }
        config.values[.trashRetentionDays] = answer.trashRetentionDays.map { .number($0) }
        config.values[.versionRecentDays] = answer.versionRecentDays.map { .number($0) }
        config.values[.versionDailyDays] = answer.versionDailySnapshotDays.map { .number($0) }
        config.values[.versionWeeklyDays] = answer.versionWeeklySnapshotDays.map { .number($0) }
        config.values[.versionMaxVersions] = answer.versionMaxVersions.map { .number($0) }
        return config
    }

    /// A body that names only the settings in `patch`: a field left out stays as it is, and `null` removes one.
    static func payload(_ patch: InstanceConfigPatch) -> Operations.UpdateConfig.Input.Body.JsonPayload {
        func number(_ setting: InstanceSetting) -> MarfaNullable<Int>? {
            if patch.clear.contains(setting) { return .null }
            if case .number(let number)? = patch.values[setting] { return .value(number) }
            return nil
        }
        var name: MarfaNullable<String>?
        if patch.clear.contains(.name) {
            name = .null
        } else if case .text(let text)? = patch.values[.name] {
            name = .value(text)
        }
        return .init(
            versionRecentDays: number(.versionRecentDays),
            versionDailySnapshotDays: number(.versionDailyDays),
            versionWeeklySnapshotDays: number(.versionWeeklyDays),
            versionMaxVersions: number(.versionMaxVersions),
            name: name,
            trashRetentionDays: number(.trashRetentionDays))
    }

    /// The server's sentence without the raw details the client appends to it.
    static func reason(_ message: String) -> String {
        message.components(separatedBy: " Details:").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? message
    }

    static func failure(_ error: any Error) -> InstanceConfigFailure {
        guard let error = error as? MarfaError else { return .failed(error.localizedDescription) }
        switch error {
        case .noConnection, .network: return .unreachable
        case .forbidden: return .notPermitted
        case .unauthorized, .signedOut: return .keyRefused
        case .validation(_, let message): return .refused(reason(message))
        default: return .failed(error.message)
        }
    }
}
