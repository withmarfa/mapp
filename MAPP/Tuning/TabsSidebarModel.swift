#if DEBUG
import Foundation

/// The tabs at the top of the tab-bar sidebar experiment (`SidebarStyle.tabs`). A tab is not state of its own: which
/// one stands selected is worked out from what the window shows, so the bar can never disagree with the window.
enum SidebarTab: String, CaseIterable, Identifiable {
    case home, items, sources, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .items: "Items"
        case .sources: "Sources"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .items: "square.grid.2x2"
        case .sources: "antenna.radiowaves.left.and.right"
        case .settings: "gearshape"
        }
    }

    /// What the window shows, as a tab. Settings and Home take precedence over the place beneath them. Items holds
    /// every list of items: a type, a collection, a view, Recents, Favorites. Inbox has an icon of its own at the end
    /// of the bar, so no tab stands selected for it.
    static func current(item: SidebarItem, home: Bool, settings: Bool) -> SidebarTab? {
        if settings { return .settings }
        if home { return .home }
        switch item {
        case .inbox: return nil
        case .sources, .source: return .sources
        default: return .items
        }
    }

    /// What choosing a tab does to the window.
    enum Move: Equatable {
        /// The tab is already what the window shows.
        case stay
        case home
        case place(SidebarItem)
        case settings
        /// Settings gives way to the place the window was showing.
        case leaveSettings
    }

    static func move(for tab: SidebarTab, item: SidebarItem, home: Bool, settings: Bool) -> Move {
        switch tab {
        case .settings: return settings ? .leaveSettings : .settings
        case .home: return home && !settings ? .stay : .home
        case .items: return rests(on: .allNotes, item, home, settings) ? .stay : .place(.allNotes)
        case .sources: return rests(on: .sources, item, home, settings) ? .stay : .place(.sources)
        }
    }

    private static func rests(on place: SidebarItem, _ item: SidebarItem, _ home: Bool, _ settings: Bool) -> Bool {
        item == place && !home && !settings
    }
}

/// The Home page's greeting for an hour of the day (0 to 23).
enum TabsGreeting {
    static func text(hour: Int) -> String {
        switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}
#endif
