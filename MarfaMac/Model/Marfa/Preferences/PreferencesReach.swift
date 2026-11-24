import Foundation

/// Whether the copy's slice takes `app.marfa-mac.preferences`.
///
/// A slice that names a type the sign-in cannot read, or one the server does not hold and the hydration could not
/// register, fails the whole hydration (the core refuses it before it clears anything), so the type joins the slice only
/// with evidence that this sign-in reaches it. A hydration refused all the same is made again without it, and the type
/// stays out until the sign-in changes (`MarfaSync`).
///
/// - The server holds the type: the sign-in holds the vendor scope or `app.*:write`, or the copy already holds the type.
///   The vendor's holder reaches it without naming it (`keys-and-oauth/app-reaches-own-vendor`).
/// - The server holds no type yet: the sign-in may register it (`PreferencesType.registeringScope`). The server offers no
///   scope naming the vendor while no type sits under it (`keys-and-oauth/app-vendor-not-named`), so the first Mac asks for
///   `app.*:write`; registering makes it the vendor's holder.
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
