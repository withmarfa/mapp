import Foundation
import Marfa

/// The one way the app writes the instance's enforcement: strict mode, the source allow-list and the source filter.
///
/// `PATCH /config` replaces all three levers together and guards only which instance is written, so a page that sent
/// back what it read earlier would undo a change made since, by another page or another device. A write through `write`
/// runs after every write started before it, one at a time, and:
///
/// 1. reads the levers again (`OwnerCalls.sourceLimit`, which reads all three);
/// 2. stops with `anotherMarfa` where another instance answers than the one the caller's page was read from;
/// 3. stops with `changedElsewhere` where `unchangedSince` says the caller's own lever is no longer as the person saw it;
/// 4. stops, sending nothing, where the sign-in no longer holds `config.manage`;
/// 5. sends what was just read with only `change` made to it, so the other levers go back as the server holds them.
///
/// Strict writes through it now. A source rule (the filter, the allow-list) joins by calling
/// `context.writeEnforcement(readFrom:unchangedSince:_:)` with the instance its page was read from, an `unchangedSince` that
/// compares only its own lever with what the page showed, and a `change` that sets only that lever on the levers it is
/// handed; the page then shows the `SourceLimit` it answers. The window between the read and the write stays open across
/// clients, as the API has no precondition for a configuration write (withmarfa/marfa#3535).
@MainActor final class EnforcementSettings {
    /// The writer every page of the app shares. A test's context makes its own.
    static let app = EnforcementSettings()

    private var isWriting = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Why a write sent nothing, or what the server refused.
    enum Failure: Error, Equatable {
        case owner(OwnerFailure)
        /// The caller's own lever changed since the person saw it; the levers as they are now.
        case changedElsewhere(SourceLimit)
        /// Another instance answers at the address than the one the page was read from.
        case anotherMarfa
    }

    /// Changes one lever as the steps above say and answers the levers the server then holds.
    func write(
        in context: OwnerContext, readFrom instanceID: String?, unchangedSince shown: (SourceLimit) -> Bool = { _ in true },
        _ change: (inout SourceLimit) -> Void
    ) async throws(Failure) -> SourceLimit {
        await begin()
        defer { end() }
        var levers: SourceLimit
        do { levers = try await context.calls.sourceLimit() } catch { throw Self.failure(error) }
        if let instanceID, let now = levers.instanceID, instanceID != now { throw .anotherMarfa }
        guard shown(levers) else { throw .changedElsewhere(levers) }
        guard context.grants().contains(.configManage) else { throw .owner(.notPermitted(InstancePermission.configManage.rawValue)) }
        change(&levers)
        do {
            return try await context.calls.setSourceLimit(levers, to: levers.isOn ? (levers.types, levers.sources) : nil)
        } catch {
            throw Self.failure(error)
        }
    }

    private static func failure(_ failure: OwnerFailure) -> Failure {
        failure == .instanceChanged ? .anotherMarfa : .owner(failure)
    }

    private func begin() async {
        guard isWriting else {
            isWriting = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func end() {
        if waiting.isEmpty { isWriting = false } else { waiting.removeFirst().resume() }
    }
}

extension OwnerContext {
    /// Changes one enforcement lever through the app's one writer, as `EnforcementSettings` says.
    func writeEnforcement(
        readFrom instanceID: String?, unchangedSince shown: (SourceLimit) -> Bool = { _ in true }, _ change: (inout SourceLimit) -> Void
    ) async throws(EnforcementSettings.Failure) -> SourceLimit {
        try await enforcement.write(in: self, readFrom: instanceID, unchangedSince: shown, change)
    }
}
