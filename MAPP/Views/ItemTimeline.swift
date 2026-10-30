import MarfaIcons
import SwiftUI

struct ItemTimeline: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var daysSeen = 0

    var body: some View {
        let _ = daysSeen
        let items = browser.items(in: library)
        let fields = browser.timelineFieldChoices(in: library)
        // Chosen in the toolbar's View Options (`ItemTimelineOptions`).
        let field = ItemTimelineLayout.selectedField(browser.timelineFields[browser.item], fields: fields)
        let groups = ItemTimelineLayout.groups(for: items, field: field, catalogue: library.catalogue)
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)

        timeline(groups)
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
        .navigationTitle(title)
        // The timeline only shows items; it changes none of them.
        .navigationSubtitle(Text("\(Text("^[\(items.count) item](inflect: true)")), Read Only"))
        .toolbar(removing: browser.isSearchExpanded ? .title : nil)
        .onChange(of: browser.isSearchExpanded) {
            if !browser.isSearchExpanded { browser.focusRequest = .list }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) { daysSeen += 1 }
        }
    }

    private func timeline(_ groups: [ItemTimelineGroup]) -> some View {
        List(selection: $browser.selection) {
            ForEach(groups) { group in
                ForEach(group.rows) { row in
                    HStack(alignment: .top, spacing: 20) {
                        dayRail(group.id)
                            .opacity(row.id == group.rows.first?.id ? 1 : 0)
                            .accessibilityHidden(row.id != group.rows.first?.id)
                            .frame(width: 112, alignment: .leading)
                        ItemTimelineEntry(row: row, catalogue: library.catalogue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 10)
                    .tag(row.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("TimelineItem-\(row.id.rawValue)")
                    .accessibilityAction(named: Text("Open")) { open([row.id]) }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .softSelection(rows: groups.flatMap { $0.rows.map(\.id.rawValue) }, selection: { browser.selection })
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

    @ViewBuilder private func dayRail(_ id: ItemTimelineGroup.ID) -> some View {
        switch id {
        case .day(let date):
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: library.now())
            let distance = calendar.dateComponents([.day], from: today, to: date).day
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if distance == 0 {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .accessibilityHidden(true)
                    }
                    switch distance {
                    case 0: Text("Today")
                    case 1: Text("Tomorrow")
                    case -1: Text("Yesterday")
                    default: Text(date, format: .dateTime.weekday(.wide))
                    }
                }
                .interfaceFont(.headline)
                .foregroundStyle(distance == 0 ? Color.accentColor : Color.primary)
                Text(date, format: .dateTime.day().month(.abbreviated).year())
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
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

private struct ItemTimelineEntry: View {
    let row: ItemTimelineRow
    let catalogue: Catalogue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: row.item.title)
                .interfaceFont(.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label { Text(catalogue.label(for: row.item.type)) } icon: { TypeIcon(name: catalogue.icon(for: row.item.type)) }
                if let source = row.item.source {
                    Text(verbatim: source)
                }
            }
            .interfaceFont(.caption)
            .foregroundStyle(.secondary)
            switch row.value {
            case .dated(let date, let dateOnly, let raw):
                if !dateOnly {
                    Text(date, format: .dateTime.hour().minute().second())
                        .interfaceFont(.caption)
                        .foregroundStyle(.secondary)
                        .help(raw)
                }
            case .invalid(let raw):
                Text(verbatim: raw)
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .missing, .notApplicable:
                EmptyView()
            }
        }
    }
}
