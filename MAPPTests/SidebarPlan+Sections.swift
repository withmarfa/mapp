import Foundation

@testable import MAPP

/// What the first tab shows of each section, read from the plan's sections, so a test says it in the sidebar's own terms.
extension SidebarPlan {
    @MainActor
    func section(_ kind: SidebarGroup.Kind) -> SidebarGroupPlan? { groups.first { $0.group.kind == kind } }

    /// The sections the first tab draws when nothing is being customized.
    @MainActor
    private var drawn: [SidebarGroupPlan] { groups(in: layout.allTabs[0].id, customizing: false) }

    @MainActor var showsLibrary: Bool { drawn.contains { $0.group.kind == .library } }
    @MainActor var showsViews: Bool { drawn.contains { $0.group.kind == .views } }
    @MainActor var showsTypes: Bool { drawn.contains { $0.group.kind == .types } }

    @MainActor var shownDestinations: [SidebarPlace] { section(.library)?.shown ?? [] }

    @MainActor var shownBuiltInViews: [SidebarPlace] { (section(.views)?.shown ?? []).filter(SidebarPlace.builtInViews.contains) }

    /// The saved views the Views section lists, in its order.
    @MainActor var shownSavedViews: [LibraryView] {
        (section(.views)?.shown ?? []).compactMap { place in
            guard case .view(let id) = place else { return nil }
            return views.first { $0.id == id }
        }
    }

    @MainActor var shownViews: [LibraryView] { shownSavedViews }

    /// The blocks below the top that have something to show: saved views, then types.
    @MainActor var shownLibrary: [SidebarPlace] { (shownSavedViews.isEmpty ? [] : [.views]) + (showsTypes ? [.types] : []) }
}
