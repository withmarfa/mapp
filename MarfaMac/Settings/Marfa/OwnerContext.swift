import Foundation
import Marfa

/// What a model of the owner's pages is lent: the calls, what the sign-in holds, and the two things a refusal does, ask
/// for more and read what is held again. A model reaches nothing else, so a test scripts all of it.
@MainActor struct OwnerContext {
    let calls: any OwnerCalls
    let grants: () -> Set<InstancePermission>
    /// Whether the sign-in holds a scope beyond the owner's permissions, such as `metadata.edge_types:write`.
    let holds: (String) -> Bool
    let allowMore: (Set<InstancePermission>) async -> MarfaAllowMoreOutcome
    let refreshGrants: () async -> Void
    /// Hands a draft over that was left behind after Settings closed, such as a key whose call ended then.
    let lateDraft: (OwnerDraft) -> Void
    /// The one writer of the instance's enforcement, shared by every page of the app.
    let enforcement: EnforcementSettings

    init(
        calls: any OwnerCalls, grants: @escaping () -> Set<InstancePermission>, holds: @escaping (String) -> Bool = { _ in false },
        allowMore: @escaping (Set<InstancePermission>) async -> MarfaAllowMoreOutcome = { _ in .cancelled },
        refreshGrants: @escaping () async -> Void = {}, lateDraft: @escaping (OwnerDraft) -> Void = { _ in },
        enforcement: EnforcementSettings = EnforcementSettings()
    ) {
        self.calls = calls
        self.grants = grants
        self.holds = holds
        self.allowMore = allowMore
        self.refreshGrants = refreshGrants
        self.lateDraft = lateDraft
        self.enforcement = enforcement
    }

    init(host: any MarfaSettingsHost) {
        self.init(
            calls: host.ownerCalls, grants: { host.grants }, holds: { host.holds($0) }, allowMore: { await host.allowMore($0) },
            refreshGrants: { await host.refreshGrants() }, lateDraft: { host.ownerDrafts.arrive($0) }, enforcement: .app)
    }

    /// What a failed call asks of the page: the grants are read again where the server says one is missing, since the owner
    /// may have narrowed the app's access from another device.
    func learn(from failure: OwnerFailure) async {
        if case .notPermitted = failure { await refreshGrants() }
    }
}
