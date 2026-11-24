import Foundation

/// Decides whether an external item link can open using the connected library's local state.
nonisolated enum ItemLinkRoute: Equatable, Sendable {
    /// Opens the item, as opening it from the list does.
    case open(ItemID)
    /// The library is still opening, so the link waits for it.
    case wait
    /// Tells the person why the link opens nothing.
    case refuse(ItemLinkRefusal)

    /// `instanceID` is the one the library's copy holds, nil while the copy has none; `holds` is whether the copy holds
    /// the item.
    static func decide(_ link: ItemAppLink, mode: Libraries.Mode, isLoaded: Bool, instanceID: String?, holds: Bool) -> ItemLinkRoute {
        switch mode {
        case .unconfigured: return .refuse(.notConnected)
        case .failed: return .refuse(.unavailable)
        case .opening: return .wait
        case .marfa:
            guard isLoaded else { return .wait }
            guard let instanceID else { return .refuse(.notFound) }
            guard instanceID.lowercased() == link.instanceID else { return .refuse(.otherMarfa) }
            return holds ? .open(link.item) : .refuse(.notFound)
        }
    }
}

/// Why a link opens nothing, in the person's words.
nonisolated enum ItemLinkRefusal: Equatable, Sendable, CaseIterable {
    /// The text is not an item's `marfa://` link.
    case malformed
    /// The link names an item in a Marfa other than the connected one.
    case otherMarfa
    /// No Marfa is connected.
    case notConnected
    /// A Marfa is connected but its library can't be opened: its sign-in was refused or its copy failed.
    case unavailable
    /// The library was still opening when the link stopped waiting.
    case stillOpening
    /// The copy doesn't hold the item, or doesn't yet know which Marfa it is.
    case notFound

    var title: String { String(localized: "Can’t Open Link") }

    var message: String {
        switch self {
        case .malformed: String(localized: "This isn’t a Marfa link.")
        case .otherMarfa: String(localized: "This link is to an item in another Marfa.")
        case .notConnected: String(localized: "This Mac isn’t connected to a Marfa. Connect to your Marfa in Settings, then open the link again.")
        case .unavailable: String(localized: "Your Marfa library can’t be opened right now. Check the connection in Settings, then open the link again.")
        case .stillOpening: String(localized: "Your Marfa library is still opening. Open the link again in a moment.")
        case .notFound: String(localized: "This item can’t be found in this Mac’s copy of your Marfa. It may have been deleted, or it may not have synced to this Mac yet.")
        }
    }

    /// Settings > Connection where connecting is the way forward. The person opens it; the link never does.
    var action: Notices.Action? {
        switch self {
        case .notConnected, .unavailable: .openSettings(.connection)
        case .malformed, .otherMarfa, .stillOpening, .notFound: nil
        }
    }
}
