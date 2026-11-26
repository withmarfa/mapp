import SwiftUI

extension TopRowMetrics {
    /// Where the title stands from the edge of a layout that spans the window, before the room the toolbar's items take
    /// (`TopRowSpace.titleLead`). It is the compact title's `listLead` while the sidebar is closed and the window is at its
    /// smallest over a layout with the page beside it (the title is then in the row below the toolbar), and `lead`
    /// otherwise. The page is beside the layout by the place's own Open Items, else `settings`, Settings'
    /// (`Browser.itemOpening(settings:)`).
    @MainActor
    static func collectionLead(browser: Browser, settings: ItemOpening, opensPlaces: Bool, isSmall: Bool) -> CGFloat {
        opensPlaces && isSmall && browser.showsBesidePage(opening: browser.itemOpening(settings: settings)) ? listLead : lead
    }
}
