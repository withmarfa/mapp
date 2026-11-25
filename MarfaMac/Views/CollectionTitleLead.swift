import SwiftUI

extension TopRowMetrics {
    /// Where the title stands from the edge of a layout that spans the window, which the layout's first column follows. It
    /// is the compact title's `listLead` while the sidebar is closed and the window is at its smallest over a layout with
    /// the page beside it (the title is then in the row below the toolbar), and `lead` otherwise. `opening` is the stored
    /// setting the title reads.
    @MainActor
    static func collectionLead(browser: Browser, opening: ItemOpening, opensPlaces: Bool, isSmall: Bool) -> CGFloat {
        opensPlaces && isSmall && browser.showsBesidePage(opening: opening) ? listLead : lead
    }
}
