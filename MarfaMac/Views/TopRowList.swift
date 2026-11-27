import SwiftUI

extension View {
    /// The top row of a list column or of a layout that spans the window: the place's title and views.
    /// `opensPlaces` is true while the sidebar is closed, when the title opens the sidebar's rows.
    /// `isSmall` is true while the window is at its smallest, where the views are one pill beside the title.
    /// `isBesidePage` is true for the list column of a list beside its page, whose title stands as far in as the rows' text.
    func topRowOverList(
        browser: Browser, scroll: TopRowScroll, opensPlaces: Bool, isSmall: Bool, isBesidePage: Bool = false, signal: AnyHashable
    ) -> some View {
        modifier(TopRowOverList(browser: browser, scroll: scroll, opensPlaces: opensPlaces, isSmall: isSmall, isBesidePage: isBesidePage, signal: signal))
    }

    /// The top row of an item's page: the item's title on one line once the page's head has scrolled off.
    func topRowOverPage(tools: ItemToolbarActions, signal: AnyHashable) -> some View {
        modifier(TopRowOverPage(tools: tools, signal: signal))
    }
}

private struct TopRowOverList: ViewModifier {
    @CurrentLibrary private var library
    @Environment(\.interfaceTextSize) private var textSize
    @AppStorage(ListKey.openItemsIn) private var opening = ItemOpening.standard
    /// Only watched: the row's order and hidden views are read through `Browser.viewChoices`.
    @AppStorage(ViewOrders.key) private var orders = Data()
    @AppStorage(ViewOrders.hiddenKey) private var hidden = Data()
    let browser: Browser
    let scroll: TopRowScroll
    let opensPlaces: Bool
    let isSmall: Bool
    let isBesidePage: Bool
    let signal: AnyHashable

    /// The layouts that stand the views beside the title from the start: the calendar has a header of its own, the
    /// board's lanes scroll by themselves and the map does not scroll, so none has rows to scroll a row of views away.
    private var isAlwaysBeside: Bool { !browser.showsPlaceIndex && (browser.viewMode == .calendar || browser.viewMode == .board || browser.viewMode == .map) }

    func body(content: Content) -> some View {
        let _ = (orders, hidden)
        let row = TopRowContent.make(browser: browser, library: library)
        // With the sidebar closed the place, its views and the buttons share one row, and so they do at the smallest window.
        // Except in a list column beside a page: there the traffic lights, the sidebar's button and Back and Forward leave
        // the first line no room for the title, so it, the scope and the views have the row below, which scrolls away. So
        // too at the smallest window over a layout with the page beside it, which leaves the layout no wider than a list.
        let isCompact = opensPlaces && isBesidePage
            || TopRowMetrics.collectionLead(browser: browser, settings: opening, opensPlaces: opensPlaces, isSmall: isSmall) == TopRowMetrics.listLead
        let beside = !isCompact && (isAlwaysBeside || browser.isSearchExpanded || browser.isSearching || opensPlaces || isSmall)
        let restHeight = (row.hasViews || isCompact) && !beside
            ? TopRowMetrics.restHeight(scale: InterfaceStyle.scale(for: textSize)) : 0
        content
            .modifier(
                TopRowFrame(
                    scroll: scroll, restHeight: restHeight, bands: true, signal: signal,
                    titleLead: { isCompact ? TopRowMetrics.listLead : $0.titleLead(base: isBesidePage ? TopRowMetrics.listLead : TopRowMetrics.lead) }
                ) { lead, room, isAway in
                    if isCompact {
                        Color.clear
                    } else {
                        TopRowTitleLine(
                            browser: browser, content: row, showsViews: row.hasViews && isAway, opensPlaces: opensPlaces, isSmall: isSmall,
                            isCovered: isBesidePage && browser.isSearchExpanded)
                            .padding(.leading, lead)
                            .padding(.trailing, room.titleTrail)
                    }
                } rest: { lead in
                    if isCompact {
                        TopRowTitleLine(
                            browser: browser, content: row, showsViews: row.hasViews, opensPlaces: true, isSmall: isSmall)
                            .padding(.leading, TopRowMetrics.listLead)
                            .padding(.trailing, TopRowMetrics.pillsTrail)
                    } else {
                        TopRowViewsLine(browser: browser, content: row)
                            .padding(.leading, lead - TopRowMetrics.pillInset)
                            .padding(.trailing, TopRowMetrics.pillsTrail)
                    }
                })
    }
}

private struct TopRowOverPage: ViewModifier {
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsScrolledTitle = true
    let tools: ItemToolbarActions
    let signal: AnyHashable

    func body(content: Content) -> some View {
        content.modifier(
            TopRowFrame(scroll: nil, restHeight: 0, bands: false, signal: signal, dragClearance: TopRowMetrics.pageLift) { lead, room, _ in
                HStack(spacing: 0) {
                    if showsScrolledTitle || tools.isFocused, let head = tools.scrolledPageTitle {
                        ScrolledItemTitle(title: head.title, icon: head.icon, showsIcon: true, subtitle: head.subtitle)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, lead)
                .padding(.trailing, room.titleTrail)
            } rest: { _ in
                EmptyView()
            })
    }
}
