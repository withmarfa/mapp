import Foundation

/// Whether the copy's slice takes `app.marfa-mac.preferences`.
///
/// A slice that names a type the sign-in cannot read, or one the server does not hold and the hydration could not
/// register, fails the whole hydration (the core refuses it before it clears anything), so the type joins the slice only
/// with evidence that this sign-in reaches it. A hydration refused all the same is made again without it, and the type
/// stays out until the sign-in changes (`MarfaSync`).
///
/// - The server holds the type: the sign-in holds `app.*:write`, which every sign-in asks for, or a scope that names the
///   vendor; or the copy already holds the type, as the sign-in that registered it does, since the vendor's holder
///   reaches it without naming it (`keys-and-oauth/app-reaches-own-vendor`).
/// - The server holds no type yet: the sign-in may register it (`PreferencesType.registeringScope`), which it may do
///   while holding `app.*:write`; registering makes it the vendor's holder (`types/app-vendor-bound`).
nonisolated enum PreferencesReach {
    /// What a sign-in and its server say, read just before a hydration.
    struct Evidence: Equatable, Sendable {
        var typeHeld: Bool
        var scopes: Set<String>
    }

    static func includes(_ evidence: Evidence, holdsTypeNow: Bool) -> Bool {
        if evidence.typeHeld {
            return holdsTypeNow || !evidence.scopes.isDisjoint(with: PreferencesType.reachingScopes)
        }
        return evidence.scopes.contains(PreferencesType.registeringScope)
    }
}
