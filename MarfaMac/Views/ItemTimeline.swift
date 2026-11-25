import SwiftUI

/// A place's items by day, in the order the browser calculated.
struct ItemTimeline: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var daysSeen = 0
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    /// What each row says, worked out once for each item from its type's look.
    @State private var rowContents = CardContents()

    var body: some View {
        let _ = daysSeen
        let items = browser.filteredItems(in: library)
        let fields = browser.timelineFieldChoices(in: library)
        // Chosen in the View panel's Timeline section (`ViewPanelLayoutRows`).
        let field = ItemTimelineLayout.selectedField(browser.timelineFields[browser.shown], fields: fields)
        let now = library.now()
        // Worked out off the main actor for a large place (`Browser.placed`); only a page of it is drawn, as the list's is.
        let placing = browser.timelinePlacing(in: library, field: field, now: now)
        let (groups, more) = placing.drawn(upTo: browser.listItemsDrawn)
        let list = RowList(
            mixesTypes: placing.types.count > 1, date: .look, format: dateFormat, datesApart: true, placedField: field, marksFeed: browser.listing.scope == .all, day: Calendar.current.startOfDay(for: now))
        let contents = rowContents.contents(
            of: groups.flatMap { $0.rows.map(\.item) }, in: library, looks: browser.propertyLooks(in: library), list: list,
            shape: CardShape(leaving: field))

        timeline(groups, more: more, contents: contents, now: now)
        .topRowScrolls()
        .clearsSeveralOnEscape(browser)
        .deletesChosen(browser) { Set(items.map(\.id)) }
        .searchStatus(browser)
        .overlay {
            if items.isEmpty {
                if browser.narrowsBySearch {
                    SearchEmptyState(browser: browser)
                } else {
                    PlaceEmptyState(browser: browser)
                }
            }
        }
        .filteredEmptyState(browser)
        .background(ChosenRowOpensSidebar(browser: browser))
        .onChange(of: browser.isSearchExpanded) {
            if !browser.isSearchExpanded { browser.focusRequest = .list }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) { daysSeen += 1 }
        }
        // An item chosen past what is drawn, as by Back or a link, is drawn.
        .onChange(of: browser.selection, initial: true) {
            if browser.selection.count == 1, let id = browser.selection.first, let position = placing.positions[id] {
                browser.drawList(through: position)
            }
        }
    }

    /// One line of a day's list: a row, or the line that marks the present moment.
    private enum Line: Identifiable {
        case row(ItemTimelineRow, startsDay: Bool, endsDay: Bool)
        case now(Date, startsDay: Bool)
        /// The header where the days ahead end and the days before begin.
        case earlier

        var id: String {
            switch self {
            case .row(let row, _, _): row.id.rawValue
            case .now: "now"
            case .earlier: "earlier"
            }
        }
    }

    private func lines(of group: ItemTimelineGroup, now: Date) -> [Line] {
        if group.id == .earlier { return [.earlier] }
        var lines = group.rows.enumerated().map { index, row in
            Line.row(row, startsDay: index == 0, endsDay: index == group.rows.count - 1)
        }
        if let at = ItemTimelineLayout.nowLine(in: group, now: now) {
            lines.insert(.now(now, startsDay: at == 0), at: at)
            // The day's divider belongs to its last line.
            if at == group.rows.count, case .row(let row, let starts, _) = lines[at - 1] {
                lines[at - 1] = .row(row, startsDay: starts, endsDay: false)
            }
        }
        return lines
    }

    private func timeline(_ groups: [ItemTimelineGroup], more: Bool, contents: [ItemID: RowContent], now: Date) -> some View {
        ScrollViewReader { proxy in
            list(groups, more: more, contents: contents, now: now)
                // The days run from today on and then back, so today's agenda is the first line of the first group.
                .onChange(of: browser.timelineTodayRequests) {
                    guard let first = groups.first.flatMap({ lines(of: $0, now: now).first }) else { return }
                    withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                }
        }
    }

    private func list(_ groups: [ItemTimelineGroup], more: Bool, contents: [ItemID: RowContent], now: Date) -> some View {
        SelectableTimeline(browser: browser) {
            ForEach(groups) { group in
                ForEach(lines(of: group, now: now)) { line in
                    switch line {
                    case .row(let row, let startsDay, let endsDay):
                        if let content = contents[row.id] {
                            HStack(alignment: .top, spacing: 0) {
                                dayRail(group.id).padding(.top, 6)
                                    .opacity(startsDay ? 1 : 0)
                                    .accessibilityHidden(!startsDay)
                                    .frame(width: 148, alignment: .leading)
                                timeColumn(row)
                                    .frame(width: 112, alignment: .leading)
                                TimelineRowView(content: content, itemID: row.id)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .tag(row.id)
                            .wantsCounts(of: row.id, content.countQueries, in: library.counts)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("TimelineItem-\(row.id.rawValue)")
                            .accessibilityAction(named: Text("Open")) { browser.open([row.id]) }
                            .listRowSeparator(endsDay ? .visible : .hidden, edges: .bottom)
                        }
                    case .earlier:
                        Text("Earlier")
                            .interfaceFont(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .selectionDisabled()
                            .listRowSeparator(.hidden)
                            .accessibilityAddTraits(.isHeader)
                    case .now(let date, let startsDay):
                        HStack(spacing: 0) {
                            dayRail(group.id)
                                .opacity(startsDay ? 1 : 0)
                                .accessibilityHidden(true)
                                .frame(width: 148, alignment: .leading)
                            Text(verbatim: DateDisplay.timeOfDay(of: date, format: dateFormat))
                                .interfaceFont(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.red)
                                .frame(width: 112, alignment: .leading)
                            Circle().fill(.red).frame(width: 6, height: 6)
                            Rectangle().fill(.red).frame(height: 1)
                        }
                        .selectionDisabled()
                        .listRowSeparator(.hidden)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Now"))
                    }
                }
            }
            if more {
                // Drawn only to come into view, which draws the next page.
                Color.clear.frame(height: 1)
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)
                    .onAppear { browser.drawMoreOfList() }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .softSelection(rows: groups.flatMap { $0.rows.map(\.id.rawValue) }, hovers: true, inert: inertRows(groups, more: more, contents: contents, now: now), selection: { browser.selection })
        .focused(pane, equals: .list)
        .takesKeyboardOnClick { browser.focusRequest = .list }
        .accessibilityLabel("Timeline")
        .accessibilityIdentifier("ItemTimeline")
        .contextMenu(forSelectionType: ItemID.self) { ids in
            ItemRowMenu(browser: browser, ids: ids, undoManager: undoManager)
        } primaryAction: { ids in
            browser.open(ids)
        }
        .onKeyPress(.return) { browser.openSelection() ? .handled : .ignored }
    }

    /// The places in the list of the rows that are not items: the Earlier heading, the line for now and the line that draws
    /// more. An item with no content yet makes no row, so it takes no place.
    private func inertRows(_ groups: [ItemTimelineGroup], more: Bool, contents: [ItemID: RowContent], now: Date) -> Set<Int> {
        var inert: Set<Int> = []
        var place = 0
        for group in groups {
            for line in lines(of: group, now: now) {
                switch line {
                case .row(let row, _, _):
                    if contents[row.id] != nil { place += 1 }
                case .earlier, .now:
                    inert.insert(place)
                    place += 1
                }
            }
        }
        if more { inert.insert(place) }
        return inert
    }

    /// The row's date is its time, so the row itself says no second date.
    @ViewBuilder private func timeColumn(_ row: ItemTimelineRow) -> some View {
        Group {
            switch row.value {
            case .dated(let date, let dateOnly, let raw):
                if dateOnly {
                    if row.isEvent { Text("All day") }
                } else {
                    Text(verbatim: DateDisplay.timeOfDay(of: date, format: dateFormat)).monospacedDigit().help(raw)
                }
            case .invalid(let raw):
                Text(verbatim: raw).lineLimit(2)
            case .missing, .notApplicable:
                EmptyView()
            }
        }
        .interfaceFont(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }

    @ViewBuilder private func dayRail(_ id: ItemTimelineGroup.ID) -> some View {
        switch id {
        case .day(let date):
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: library.now())
            let distance = calendar.dateComponents([.day], from: today, to: date).day
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    switch distance {
                    case 0: Text("Today")
                    case 1: Text("Tomorrow")
                    case -1: Text("Yesterday")
                    default: Text(date, format: .dateTime.weekday(.wide))
                    }
                }
                .interfaceFont(.headline)
                .foregroundStyle(distance == 0 ? Color.red : Color.primary)
                let named = distance.map { abs($0) <= 1 } ?? false
                let sameYear = calendar.isDate(date, equalTo: today, toGranularity: .year)
                let format = Date.FormatStyle().day().month(.abbreviated)
                // A chosen way of writing a date replaces the system's short one under the day's name.
                Group {
                    if dateFormat.date == .system {
                        Text(date, format: named ? format.weekday(.wide) : sameYear ? format : format.year())
                    } else {
                        Text(verbatim: DateDisplay.text(of: date, hasTime: false, place: .value, format: dateFormat))
                    }
                }
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
        case .earlier:
            EmptyView()
        case .missing:
            Text("No Date").interfaceFont(.headline).foregroundStyle(.secondary)
        case .invalid:
            Text("Invalid Date").interfaceFont(.headline).foregroundStyle(.secondary)
        case .notApplicable:
            Text("Not Applicable").interfaceFont(.headline).foregroundStyle(.secondary)
        }
    }
}

/// Binds the native list's selection to the window.
private struct SelectableTimeline<Content: View>: View {
    @Bindable var browser: Browser
    @ViewBuilder var content: Content

    var body: some View {
        List(selection: $browser.selection) { content }
    }
}

/// Opens the right sidebar when the person chooses a single item in the timeline or calendar.
struct ChosenRowOpensSidebar: View {
    /// The window's, which the right sidebar is shown through.
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let browser: Browser

    var body: some View {
        Color.clear.onChange(of: browser.selection) { _, selection in
            if selection.count == 1, browser.showsCollection, !browser.isModalPresented { details?.isPresented = true }
        }
    }
}
