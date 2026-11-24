import Marfa

/// What the Types page asks of the app that holds it: how many items a type holds, the icon a type shows now and the one
/// call that changes it, which the app makes through its library so the icon shows at once. All in the app's own terms, so
/// a test scripts them.
struct TypeAccess {
    var ownItems: (String) -> Int
    var currentIcon: (String) -> String?
    var setIcon: (String?, String) async -> OwnerFailure?
    var markSets: [MarfaMarkSet]
    var marks: (String, MarfaMarkSet) -> [String]
    /// The plural the working copy reads for a type, which a type that declares none shows by the regular rule.
    var plural: (String) -> String?
}
