import SwiftUI

extension View {
    /// The top row of a list column or of a layout that spans the window: the place's title and views.
    /// `opensPlaces` is true while the sidebar is closed, when the title opens the sidebar's rows.
    func topRowOverList(browser: Browser, scroll: TopRowScroll, opensPlaces: Bool, signal: AnyHashable) -> some View {
        modifier(TopRowOverList(browser: browser, scroll: scroll, opensPlaces: opensPlaces, signal: signal))
    }

    /// The top row of an item's page: the item's title on one line once the page's head has scrolled off.
    func topRowOverPage(tools: ItemToolbarActions, signal: AnyHashable) -> some View {
        modifier(TopRowOverPage(tools: tools, signal: signal))
    }
}

private struct TopRowOverList: ViewModifier {
    @CurrentLibrary private var library
    let browser: Browser
    let scroll: TopRowScroll
    let opensPlaces: Bool
    let signal: AnyHashable

    /// The layouts that stand the views beside the title from the start: the calendar has a header of its own and the
    /// board's lanes scroll by themselves, so neither has rows to scroll a row of views away.
    private var isAlwaysBeside: Bool { browser.viewMode == .calendar || browser.viewMode == .board }

    func body(content: Content) -> some View {
        let row = TopRowContent.make(browser: browser, library: library)
        let beside = isAlwaysBeside || browser.isSearchExpanded || browser.isSearching
        let restHeight = row.hasViews && !beside ? TopRowMetrics.restHeight : 0
        content
            .environment(\.topRowSpace, TopRowSpace(scroll: scroll, restHeight: restHeight))
            .modifier(
                TopRowFrame(scroll: scroll, restHeight: restHeight, bands: true, signal: signal) { room, isAway in
                    TopRowTitleLine(browser: browser, content: row, showsViews: row.hasViews && isAway, opensPlaces: opensPlaces)
                        .padding(.leading, room.titleLead)
                        .padding(.trailing, room.titleTrail)
                } rest: {
                    TopRowViewsLine(browser: browser, content: row)
                        .padding(.leading, TopRowMetrics.pillsLead)
                        .padding(.trailing, TopRowMetrics.pillsLead)
                })
    }
}

private struct TopRowOverPage: ViewModifier {
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsScrolledTitle = true
    let tools: ItemToolbarActions
    let signal: AnyHashable

    func body(content: Content) -> some View {
        content.modifier(
            TopRowFrame(scroll: nil, restHeight: 0, bands: false, signal: signal) { room, _ in
                HStack(spacing: 0) {
                    if showsScrolledTitle || tools.isFocused, let head = tools.scrolledPageTitle {
                        ScrolledItemTitle(title: head.title, icon: head.icon, showsIcon: true, subtitle: head.subtitle)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, room.titleLead)
                .padding(.trailing, room.titleTrail)
            } rest: {
                EmptyView()
            })
    }
}
