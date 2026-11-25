import Foundation

@testable import MarfaMac

/// What the first tab shows of each section, read from the plan's sections, so a test says it in the sidebar's own terms.
extension SidebarPlan {
    @MainActor
    func section(_ kind: SidebarGroup.Kind) -> SidebarGroupPlan? { groups.first { $0.group.kind == kind } }

    /// The saved views Pinned lists, in its order.
    @MainActor var shownViews: [LibraryView] {
        (section(.pinned)?.shown ?? []).compactMap { place in
            guard case .view(let id) = place else { return nil }
            return views.first { $0.id == id }
        }
    }
}
