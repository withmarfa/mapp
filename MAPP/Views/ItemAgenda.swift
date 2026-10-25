import SwiftUI

struct ItemAgenda: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    @Binding var selectedField: String?
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var daysSeen = 0

    var body: some View {
        let _ = daysSeen
        let items = browser.items(in: library)
        let fields = ItemAgendaLayout.fields(for: items, catalogue: library.catalogue)
        let field = ItemAgendaLayout.selectedField(selectedField, fields: fields)
        let groups = ItemAgendaLayout.groups(for: items, field: field, catalogue: library.catalogue)
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)

        VStack(spacing: 0) {
            HStack {
                if !fields.isEmpty {
                    Picker("Date Field", selection: Binding(get: { field }, set: { selectedField = $0 })) {
                        ForEach(fields) { field in
                            Text(verbatim: field.displayLabel).tag(Optional(field.key))
                        }
                    }
                    .fixedSize()
                    .accessibilityIdentifier("AgendaDateField")
                }
                Spacer()
                Text("Read Only")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            agenda(groups)
                .overlay {
                    if items.isEmpty {
                        if browser.isSearching {
                            EmptyState.search(browser.searchText)
                        } else {
                            EmptyState("No Items")
                        }
                    }
                }
        }
        .navigationTitle(title)
        .navigationSubtitle(Text("^[\(items.count) item](inflect: true)"))
        .toolbar(removing: browser.isSearchExpanded ? .title : nil)
        .onChange(of: browser.isSearchExpanded) {
            if !browser.isSearchExpanded { browser.focusRequest = .list }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) { daysSeen += 1 }
        }
    }

    private func agenda(_ groups: [ItemAgendaGroup]) -> some View {
        List(selection: $browser.selection) {
            ForEach(groups) { group in
                ForEach(group.rows) { row in
                    HStack(alignment: .top, spacing: 20) {
                        dayRail(group.id)
                            .opacity(row.id == group.rows.first?.id ? 1 : 0)
                            .accessibilityHidden(row.id != group.rows.first?.id)
                            .frame(width: 112, alignment: .leading)
                        ItemAgendaEntry(row: row, catalogue: library.catalogue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 10)
                    .tag(row.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("AgendaItem-\(row.id.rawValue)")
                    .accessibilityAction(named: Text("Open")) { open([row.id]) }
                }
            }
        }
        .listStyle(.inset)
        .focused(pane, equals: .list)
        .accessibilityLabel("Agenda")
        .accessibilityIdentifier("ItemAgenda")
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

    @ViewBuilder private func dayRail(_ id: ItemAgendaGroup.ID) -> some View {
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

private struct ItemAgendaEntry: View {
    let row: ItemAgendaRow
    let catalogue: Catalogue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: row.item.title)
                .interfaceFont(.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(TypeSymbol.label(for: row.item.type, in: catalogue), systemImage: TypeSymbol.name(for: row.item.type, in: catalogue))
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
