import Foundation
import Marfa

/// The calls that ask the Marfa server itself instead of the working copy: an item's snapshots (Version History),
/// the server's own settings (This Marfa) and the owner's icon for a type. They need a connection, so they fail while
/// the server cannot be reached. Every call goes through the package's `Server`, with the address and the key read
/// from the key store on each call, so a key the person has since replaced is the one used. `Server` calls go over
/// `URLSession`, so App Transport Security applies to a plain http address, unlike the copy, which goes through the
/// package's core.
nonisolated struct MarfaServerCalls: ItemHistorySource, InstanceConfigSource, TypeIconSource {
    let connection: MarfaConnection
    let keys: any KeyStore
    /// How long a call waits for the server before it fails, so an unreachable server never leaves a page waiting.
    var timeout = Server.defaultTimeout

    /// How a call to the server ends, in the words of the page that made it.
    enum Ending: Error, Hashable {
        case unreachable, keyRefused, notPermitted
        /// The server holds nothing at the address asked for.
        case notFound(String)
        /// Another instance answers at the address.
        case instanceChanged(String)
        /// The server's own sentence for why it refused the request.
        case refused(String)
        case failed(String)
    }

    /// The server with the key kept for its address. A key the store cannot read is told as that, never as missing or
    /// refused, and nothing is sent.
    func server() throws(Ending) -> Server {
        let stored: String?
        do { stored = try keys.key(for: connection.address) } catch { throw .failed(Words.keyUnreadable) }
        guard let key = stored, !key.isEmpty else { throw .keyRefused }
        return connection.server(key: key)
    }

    /// What the package's error stands for, by its own classes: away, a refused key, or what the server said.
    static func ending(_ error: any Error) -> Ending {
        guard let error = error as? MarfaError else { return .failed(error.localizedDescription) }
        if error.isOffline { return .unreachable }
        if error.isKeyRefusal { return .keyRefused }
        switch error {
        case .forbidden: return .notPermitted
        case .notFound: return .notFound(error.message)
        case .validation(_, let message): return .refused(reason(message))
        case .instanceChanged: return .instanceChanged(error.message)
        default: return .failed(error.message)
        }
    }

    /// The server's sentence without the raw details the client appends to it.
    static func reason(_ message: String) -> String {
        message.components(separatedBy: " Details:").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? message
    }

    // MARK: Version History (`GET /items/{id}/versions`)

    @concurrent func page(of id: ItemID, after cursor: String?, limit: Int) async throws(ItemHistoryFailure) -> ItemHistoryPage {
        do {
            let page = try await server().snapshots(ofItem: id.rawValue, after: cursor, limit: limit, timeout: timeout)
            return ItemHistoryPage(snapshots: page.snapshots.map(Self.snapshot), next: page.next)
        } catch let ending as Ending {
            throw Self.historyFailure(ending)
        } catch {
            throw Self.historyFailure(Self.ending(error))
        }
    }

    static func historyFailure(_ ending: Ending) -> ItemHistoryFailure {
        switch ending {
        case .unreachable: .unreachable
        case .keyRefused: .keyRefused
        case .notPermitted: .notPermitted
        case .notFound: .unavailable
        case .instanceChanged(let message), .refused(let message), .failed(let message): .failed(message)
        }
    }

    static func snapshot(_ version: Marfa.ItemSnapshot) -> ItemSnapshot {
        ItemSnapshot(
            id: version.id, version: version.version, type: TypeID(version.type),
            properties: properties(version.properties), written: version.occurredAt?.date,
            writer: version.writer.map { writer in
                ItemSnapshot.Writer(kind: kind(writer.kind), name: writer.name)
            })
    }

    private static func kind(_ kind: Marfa.ItemSnapshot.Writer.Kind) -> ItemSnapshot.Writer.Kind {
        switch kind {
        case .browser: .browser
        case .app: .app
        case .key: .key
        case .local: .local
        case .other: .key
        }
    }

    private static func properties(_ object: JSONObject) -> [String: PropertyValue] {
        guard case .object(let properties) = MarfaMapping.value(.object(object)) else { return [:] }
        return properties
    }

    // MARK: This Marfa (`GET` and `PATCH /config`, which need `config.manage`)

    @concurrent func read() async throws(InstanceConfigFailure) -> InstanceConfig {
        do {
            return Self.config(try await server().config(timeout: timeout))
        } catch let ending as Ending {
            throw Self.configFailure(ending)
        } catch {
            throw Self.configFailure(Self.ending(error))
        }
    }

    @concurrent func update(_ patch: InstanceConfigPatch, expecting instanceID: String?) async throws(InstanceConfigFailure) -> InstanceConfig {
        do {
            return Self.config(try await server().updateConfig(Self.patch(patch), expecting: instanceID, timeout: timeout))
        } catch let ending as Ending {
            throw Self.configFailure(ending)
        } catch {
            throw Self.configFailure(Self.ending(error))
        }
    }

    static func configFailure(_ ending: Ending) -> InstanceConfigFailure {
        switch ending {
        case .unreachable: .unreachable
        case .keyRefused: .keyRefused
        case .notPermitted: .notPermitted
        case .instanceChanged: .instanceChanged
        case .refused(let reason): .refused(reason)
        case .notFound(let message), .failed(let message): .failed(message)
        }
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

    // MARK: Type icons (`PUT` and `DELETE /types/{id}/icon`, which need `schema.write` and write on the type)

    @concurrent func setIcon(_ icon: String?, ofType type: TypeID) async throws(TypeIconFailure) -> String? {
        do {
            return try await server().setTypeIcon(icon, ofType: type.rawValue, timeout: timeout)
        } catch let ending as Ending {
            throw Self.iconFailure(ending)
        } catch {
            throw Self.iconFailure(Self.ending(error))
        }
    }

    static func iconFailure(_ ending: Ending) -> TypeIconFailure {
        switch ending {
        case .unreachable: .unreachable
        case .keyRefused: .keyRefused
        case .notPermitted: .notPermitted
        case .refused(let reason): .refused(reason)
        case .notFound(let message), .instanceChanged(let message), .failed(let message): .failed(message)
        }
    }
}
