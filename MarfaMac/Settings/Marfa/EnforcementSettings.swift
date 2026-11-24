import Foundation
import Marfa

/// The one way the app writes the instance's enforcement: strict mode, the source allow-list and the source filter.
///
/// `PATCH /config` replaces all three levers together and guards only which instance is written, so a page that sent
/// back what it read earlier would undo a change made since, by another page or another device. Every enforcement write
/// in the app goes through `write`, one at a time, and each:
///
/// 1. waits for the writes started before it;
/// 2. reads `/config` again;
/// 3. stops with `anotherMarfa` where another instance answers than the one the caller's page was read from;
/// 4. stops with `changedElsewhere` where `unchangedSince` says the caller's own lever is no longer as the person saw it;
/// 5. stops, sending nothing, where the sign-in no longer holds `config.manage`;
/// 6. sends what was just read with only `change` made to it, so the other levers go back as the server holds them.
///
/// A page writes through its context, as `try await context.writeEnforcement(readFrom: shown.instanceID, unchangedSince:
/// { $0.filter == shown.filter }) { $0.filter = chosen }`, and shows the `Enforcement` it answers. The window between the read and the
/// write is left open across clients, as the API has no precondition for a configuration write (withmarfa/marfa#3535).
@MainActor final class EnforcementSettings {
    /// The writer every page of the app shares. A test's context makes its own.
    static let app = EnforcementSettings()

    private var isWriting = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Why a write sent nothing, or what the server refused.
    enum Failure: Error, Equatable {
        case owner(OwnerFailure)
        /// The caller's own lever changed since the person saw it; the levers as they are now.
        case changedElsewhere(Enforcement)
        /// Another instance answers at the address than the one the page was read from.
        case anotherMarfa
    }

    /// Changes one lever as the steps above say and answers the levers the server then holds.
    func write(
        in context: OwnerContext, readFrom instanceID: String?, unchangedSince shown: (Enforcement) -> Bool = { _ in true },
        _ change: (inout Enforcement) -> Void
    ) async throws(Failure) -> Enforcement {
        await begin()
        defer { end() }
        var current: Enforcement
        do { current = try await context.calls.enforcement() } catch { throw Self.failure(error) }
        if let instanceID, let now = current.instanceID, instanceID != now { throw .anotherMarfa }
        guard shown(current) else { throw .changedElsewhere(current) }
        guard context.grants().contains(.configManage) else { throw .owner(.notPermitted(InstancePermission.configManage.rawValue)) }
        change(&current)
        do { return try await context.calls.setEnforcement(current) } catch { throw Self.failure(error) }
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
        readFrom instanceID: String?, unchangedSince shown: (Enforcement) -> Bool = { _ in true }, _ change: (inout Enforcement) -> Void
    ) async throws(EnforcementSettings.Failure) -> Enforcement {
        try await enforcement.write(in: self, readFrom: instanceID, unchangedSince: shown, change)
    }
}
