import Foundation

/// Decides whether an external item link can open using the connected library's local state.
nonisolated enum ItemLinkRoute: Equatable, Sendable {
    /// Opens the item, as opening it from the list does.
    case open(ItemID)
    /// The library is still opening, so the link waits for it.
    case wait
    /// Tells the person why the link opens nothing.
    case refuse(ItemLinkRefusal)

    /// `instanceID` is the one the library's copy holds, nil while the copy has none; `held` is the state of the item
    /// in the copy, nil where the copy doesn't hold it.
    static func decide(_ link: ItemAppLink, mode: Libraries.Mode, isLoaded: Bool, instanceID: String?, held: ItemState?) -> ItemLinkRoute {
        switch mode {
        case .unconfigured: return .refuse(.notConnected)
        case .failed: return .refuse(.unavailable)
        case .opening: return .wait
        case .marfa:
            guard isLoaded else { return .wait }
            guard let instanceID else { return .refuse(.instanceUnknown) }
            guard instanceID.lowercased() == link.instanceID else { return .refuse(.otherMarfa) }
            switch held {
            case nil: return .refuse(.notFound)
            // Showing it would open Settings at Trash, which reads the server; the person chooses that.
            case .trashed: return .refuse(.inRecentlyDeleted)
            case .active, .archived: return .open(link.item)
            }
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
    /// The library was still opening, or its copy hadn't said which Marfa it is, when the link stopped waiting.
    case stillOpening
    /// The copy doesn't hold the item.
    case notFound
    /// The copy doesn't yet know which Marfa it is, so the link can't be checked.
    case instanceUnknown
    /// The item is in Recently Deleted.
    case inRecentlyDeleted

    var title: String { String(localized: "Can’t Open Link") }

    var message: String {
        switch self {
        case .malformed: String(localized: "This isn’t a Marfa link.")
        case .otherMarfa: String(localized: "This link is to an item in another Marfa.")
        case .notConnected: String(localized: "This Mac isn’t connected to a Marfa. Connect to your Marfa in Settings, then open the link again.")
        case .unavailable: String(localized: "Your Marfa library can’t be opened right now. Check the connection in Settings, then open the link again.")
        case .stillOpening: String(localized: "Marfa for Mac couldn’t check this link in time. Try opening it again.")
        case .notFound: String(localized: "This item can’t be found in this Mac’s copy of your Marfa. It may have been deleted, or it may not have synced to this Mac yet.")
        case .instanceUnknown: String(localized: "Marfa for Mac can’t check this link yet. Try again once your Marfa has finished syncing.")
        case .inRecentlyDeleted: String(localized: "This item is in Recently Deleted.")
        }
    }

    /// The Settings page where the person can go on: Connection to connect, Trash to find the item. The
    /// person opens it; the link never does.
    var action: Notices.Action? {
        switch self {
        case .notConnected, .unavailable: .openSettings(.connection)
        case .inRecentlyDeleted: .openSettings(.trash)
        case .malformed, .otherMarfa, .stillOpening, .notFound, .instanceUnknown: nil
        }
    }
}
