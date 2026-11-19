import SwiftUI

struct ItemTimeline: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var daysSeen = 0
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    /// What each row says, worked out once for each item from its type's look.
    @State private var rowContents = CardContents()

    var body: some View {
        let _ = daysSeen
        let items = browser.filteredItems(in: library)
        let fields = browser.timelineFieldChoices(in: library)
        // Chosen in the toolbar's View Options (`ItemTimelineOptions`).
        let field = ItemTimelineLayout.selectedField(browser.timelineFields[browser.item], fields: fields)
        let looks = browser.looks(in: library)
        let now = library.now()
        let groups = ItemTimelineLayout.groups(
            for: items, field: field, looks: looks, catalogue: library.catalogue, today: now)
        let list = RowList(
            mixesTypes: Set(items.map(\.type)).count > 1, date: .look, format: dateFormat, datesApart: true, placedField: field, day: Calendar.current.startOfDay(for: now))
        let contents = rowContents.contents(of: items, in: library, looks: looks, list: list, shape: CardShape())
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)

        timeline(groups, contents: contents, now: now)
        .bandsToolbar()
        .searchStatus(browser)
        .overlay {
            if items.isEmpty {
                if browser.isSearching {
                    SearchEmptyState(browser: browser)
                } else {
                    EmptyState("No Items")
                }
            }
        }
        .filteredEmptyState(browser)
        .navigationTitle(title)
        .navigationSubtitle(Text("^[\(items.count) item](inflect: true)").editedSubtitle(browser.hasViewChanges))
        .background(ChosenRowOpensSidebar(browser: browser))
        .toolbar(removing: browser.isSearchExpanded ? .title : nil)
        .onChange(of: browser.isSearchExpanded) {
            if !browser.isSearchExpanded { browser.focusRequest = .list }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) { daysSeen += 1 }
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

    private func timeline(_ groups: [ItemTimelineGroup], contents: [ItemID: RowContent], now: Date) -> some View {
        List(selection: $browser.selection) {
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
                                ItemRow(content: content)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .tag(row.id)
                            .wantsCounts(of: row.id, content.countQueries, in: library.counts)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("TimelineItem-\(row.id.rawValue)")
                            .accessibilityAction(named: Text("Open")) { open([row.id]) }
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
                            Text(date, format: .dateTime.hour().minute())
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
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .softSelection(rows: groups.flatMap { $0.rows.map(\.id.rawValue) }, hovers: true, selection: { browser.selection })
        .focused(pane, equals: .list)
        .takesKeyboardOnClick { browser.focusRequest = .list }
        .accessibilityLabel("Timeline")
        .accessibilityIdentifier("ItemTimeline")
        .contextMenu(forSelectionType: ItemID.self) { ids in
            if ids.count == 1 {
                Button("Open") { open(ids) }
            }
        } primaryAction: { ids in
            open(ids)
        }
        .onKeyPress(.return) {
            guard browser.selection.count == 1 else { return .ignored }
            browser.openCollectionSelection()
            return .handled
        }
    }

    /// The row's date is its time, so the row itself says no second date.
    @ViewBuilder private func timeColumn(_ row: ItemTimelineRow) -> some View {
        Group {
            switch row.value {
            case .dated(let date, let dateOnly, let raw):
                if dateOnly {
                    if row.isEvent { Text("All day") }
                } else {
                    Text(verbatim: DateDisplay.timeOfDay(of: date)).monospacedDigit().help(raw)
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
                Text(date, format: named ? format.weekday(.wide) : sameYear ? format : format.year())
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

    private func open(_ ids: Set<ItemID>) {
        guard ids.count == 1 else { return }
        browser.selection = ids
        browser.openCollectionSelection()
    }
}

/// Opens the right sidebar when a row is chosen. It reads the selection itself, so the timeline's body does not, and a
/// change of selection does not work out every row again. The calendar uses it too.
struct ChosenRowOpensSidebar: View {
    /// The window's, which the right sidebar is shown through.
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let browser: Browser

    var body: some View {
        Color.clear.onChange(of: browser.selection) { _, selection in
            if selection.count == 1, browser.showsCollection { details?.isPresented = true }
        }
    }
}
