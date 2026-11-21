import Foundation
import Marfa

/// What a model of the owner's pages is lent: the calls, what the sign-in holds, and the two things a refusal does, ask
/// for more and read what is held again. A model reaches nothing else, so a test scripts all of it.
@MainActor struct OwnerContext {
    let calls: any OwnerCalls
    let grants: () -> Set<InstancePermission>
    let allowMore: (Set<InstancePermission>) async -> MarfaAllowMoreOutcome
    let refreshGrants: () async -> Void

    init(
        calls: any OwnerCalls, grants: @escaping () -> Set<InstancePermission>,
        allowMore: @escaping (Set<InstancePermission>) async -> MarfaAllowMoreOutcome = { _ in .cancelled },
        refreshGrants: @escaping () async -> Void = {}
    ) {
        self.calls = calls
        self.grants = grants
        self.allowMore = allowMore
        self.refreshGrants = refreshGrants
    }

    init(host: any MarfaSettingsHost) {
        self.init(
            calls: host.ownerCalls, grants: { host.grants }, allowMore: { await host.allowMore($0) },
            refreshGrants: { await host.refreshGrants() })
    }

    /// What a failed call asks of the page: the grants are read again where the server says one is missing, since the owner
    /// may have narrowed MAPP's access from another device.
    func learn(from failure: OwnerFailure) async {
        if case .notPermitted = failure { await refreshGrants() }
    }
}
