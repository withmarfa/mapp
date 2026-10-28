#if DEBUG
import SwiftUI

/// The sidebar design experiment: a short list in the manner of the Claude app. New and Search act, a few places
/// open, More holds the rest, and favorites sit below as Pinned. Every place the real sidebar reaches is reachable
/// here, and the foot is the real one. Its text is not localized.
struct ExperimentSidebar: View {
    @CurrentLibrary private var library
    let browser: Browser
    let order: NoteOrder
    @AppStorage(ExperimentMainBlock.storageKey) private var storedBlock = ExperimentMainBlock.defaultStored
    @AppStorage("experiment.sidebar.showsMore") private var showsMore = false
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    @AppStorage(SidebarTypeRow.subtypeIconsKey) private var showsSubtypeIcons = false
    @State private var collapsed: Set<String> = []
    @State private var editsBlock = false

    /// Items opens the landing page; every other place opens as in the real sidebar.
    private var selection: Binding<SidebarItem?> {
        Binding {
            browser.showsSettings ? nil : browser.sidebarItem
        } set: { item in
            guard let item else { return }
            if item == .allNotes {
                browser.show(item, in: library, order: order)
                browser.landing = true
            } else if item == browser.sidebarItem {
                browser.leaveSettings()
            } else {
                browser.show(item, in: library, order: order)
            }
        }
    }

    var body: some View {
        let block = ExperimentMainBlock(stored: storedBlock)
        let tree = library.typeTree
        let rows = typeRows(tree.filter { !block.contains(ExperimentMainBlock.typeKey($0.id)) })
        let pinned = pinnedItems
        List(selection: selection) {
            Section {
                actionRow("New", symbol: "square.and.pencil") { browser.openQuickAdd(remembered: lastType, in: library) }
                    .accessibilityIdentifier("ExperimentNew")
                actionRow("Search", symbol: "magnifyingglass") { browser.palette = .search }
                    .accessibilityIdentifier("ExperimentSearch")
                ForEach(block.keys, id: \.self) { placeRow($0) }
                moreRow
            }
            if showsMore { moreSections(block, rows: rows) }
            if !pinned.isEmpty { pinnedSection(pinned) }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFoot(browser: browser) }
        .softSelection(
            rows: block.keys + [String(showsMore)] + collapsed.sorted() + pinned.map(\.id.rawValue) + library.views.map(\.id.rawValue)
                + tree.map(\.id),
            selection: browser.sidebarItem)
        .accessibilityIdentifier("Sidebar")
        .onChange(of: pinned.map(\.id)) { browser.placeRemoved(in: library, order: order) }
        .onChange(of: library.views.map(\.id)) { browser.placeRemoved(in: library, order: order) }
    }

    // MARK: Rows

    private func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SidebarLabel(title: title, icon: .symbol(symbol)).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .selectionDisabled()
    }

    private var moreRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { showsMore.toggle() }
        } label: {
            HStack {
                SidebarLabel(title: "More", icon: .symbol("ellipsis"))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .interfaceFont(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(showsMore ? 90 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .accessibilityValue(Text(verbatim: showsMore ? "Expanded" : "Collapsed"))
        .accessibilityIdentifier("ExperimentMore")
    }

    private struct PlaceLook {
        let title: String
        let icon: RowIcon
        let counted: Bool
    }

    private func look(ofKey key: String) -> PlaceLook? {
        switch key {
        case "all": return PlaceLook(title: "Items", icon: .symbol("square.grid.2x2"), counted: true)
        case "sources": return PlaceLook(title: library.name(of: .sources), icon: .symbol("antenna.radiowaves.left.and.right"), counted: false)
        case "collections": return PlaceLook(title: library.name(of: .collections), icon: .symbol("square.stack"), counted: false)
        case "inbox": return PlaceLook(title: library.name(of: .inbox), icon: .symbol("tray"), counted: true)
        case "recents": return PlaceLook(title: library.name(of: .recents), icon: .symbol("clock"), counted: false)
        case "favorites": return PlaceLook(title: library.name(of: .favorites), icon: .symbol("heart"), counted: true)
        case "deleted": return PlaceLook(title: library.name(of: .recentlyDeleted), icon: .symbol("trash"), counted: false)
        default:
            if key.hasPrefix(ExperimentMainBlock.typePrefix) {
                let type = TypeID(String(key.dropFirst(ExperimentMainBlock.typePrefix.count)))
                guard library.catalogue.itemTypes[type] != nil else { return nil }
                return PlaceLook(title: library.catalogue.label(for: type), icon: .type(library.catalogue.icon(for: type)), counted: true)
            }
            return nil
        }
    }

    @ViewBuilder private func placeRow(_ key: String) -> some View {
        if let item = ExperimentMainBlock.item(forKey: key), let look = look(ofKey: key) {
            let count = look.counted ? library.count(in: item) : 0
            SidebarLabel(title: look.title, icon: look.icon)
                .badge(count > 0 ? Text(count, format: .number).monospacedDigit() : nil)
                .tag(item)
                .accessibilityIdentifier("ExperimentPlace-\(key)")
        }
    }

    // MARK: More

    @ViewBuilder private func moreSections(_ block: ExperimentMainBlock, rows: [SidebarPlan.TypeRow]) -> some View {
        Section {
            ForEach(ExperimentMainBlock.placeKeys.filter { !block.contains($0) }, id: \.self) { placeRow($0) }
            Button { editsBlock = true } label: {
                SidebarLabel(title: "Edit Sidebar", icon: .symbol("slider.horizontal.3")).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .selectionDisabled()
            .popover(isPresented: $editsBlock) {
                ExperimentBlockEditor(stored: $storedBlock, candidates: candidates)
            }
            .accessibilityIdentifier("ExperimentEdit")
        } header: {
            Text(verbatim: "More")
        }
        if !rows.isEmpty {
            let steps = SidebarTypeRow.steps(for: rows, subtypeIcons: showsSubtypeIcons)
            let widest = rows.filter(\.isExpandable).map(count(of:)).max() ?? 0
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    typeRow(row, widestFoldingCount: widest, steps: steps[index])
                }
            } header: {
                Text(verbatim: "Types")
            }
        }
        if !library.views.isEmpty {
            Section {
                ForEach(library.views) { view in
                    SidebarLabel(title: view.title, icon: .symbol(SidebarPlace.viewSymbol))
                        .tag(SidebarItem.view(view.id))
                }
            } header: {
                Text(verbatim: "Views")
            }
        }
    }

    /// Type rows as the real sidebar draws them, folded by this view's own state so the real layout is left alone.
    @ViewBuilder private func typeRow(_ row: SidebarPlan.TypeRow, widestFoldingCount: Int, steps: [SidebarTypeRow.Step]) -> some View {
        let node = row.node
        let content = SidebarTypeRow(
            row: row, count: count(of: row), widestFoldingCount: widestFoldingCount, steps: steps,
            showsIcon: SidebarTypeRow.showsIcon(row, subtypeIcons: showsSubtypeIcons), toggle: { toggle(row) })
        if node.opens, let type = node.type {
            content
                .tag(SidebarItem.itemType(type.rawValue))
                .listRowInsets(.vertical, 0)
        } else {
            Button { toggle(row) } label: { content.contentShape(.rect) }
                .buttonStyle(.plain)
                .selectionDisabled()
                .listRowInsets(.vertical, 0)
        }
    }

    private func typeRows(_ nodes: [TypeNode], depth: Int = 0) -> [SidebarPlan.TypeRow] {
        nodes.flatMap { node in
            let isExpanded = !collapsed.contains(node.id)
            return [SidebarPlan.TypeRow(node: node, depth: depth, isExpanded: isExpanded)]
                + (isExpanded ? typeRows(node.children, depth: depth + 1) : [])
        }
    }

    private func count(of row: SidebarPlan.TypeRow) -> Int {
        guard row.node.opens, let type = row.node.type else { return 0 }
        return library.count(in: .itemType(type.rawValue))
    }

    private func toggle(_ row: SidebarPlan.TypeRow) {
        withAnimation(.snappy(duration: 0.2)) {
            if row.isExpanded { collapsed.insert(row.node.id) } else { collapsed.remove(row.node.id) }
        }
    }

    /// What the Edit list offers for the main block: every place, then each top-level type.
    private var candidates: [ExperimentBlockEditor.Candidate] {
        let places = ExperimentMainBlock.placeKeys.compactMap { key in
            look(ofKey: key).map { ExperimentBlockEditor.Candidate(key: key, title: $0.title, icon: $0.icon) }
        }
        let types = library.typeTree.filter(\.opens).compactMap { node in
            node.type.map {
                ExperimentBlockEditor.Candidate(
                    key: ExperimentMainBlock.typeKey($0.rawValue), title: node.label, icon: .type(node.icon))
            }
        }
        return places + types
    }

    // MARK: Pinned

    private var pinnedItems: [Item] {
        library.items(in: .favorites).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func pinnedSection(_ items: [Item]) -> some View {
        Section {
            ForEach(items) { item in
                SidebarLabel(
                    title: item.title.isEmpty ? String(localized: "Untitled") : item.title,
                    icon: .type(library.catalogue.icon(for: item.type))
                )
                .tag(SidebarItem.favoriteItem(item.id))
            }
        } header: {
            Text(verbatim: "Pinned")
        }
        .accessibilityIdentifier("ExperimentPinned")
    }
}

/// The popover that chooses which places stand above More. A place that is ticked leaves More and a place that is
/// not ticked goes back into it.
private struct ExperimentBlockEditor: View {
    struct Candidate: Identifiable {
        let key: String
        let title: String
        let icon: RowIcon
        var id: String { key }
    }

    @Binding var stored: String
    let candidates: [Candidate]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Show in the main list")
                .font(.headline)
            Text(verbatim: "The rest stay under More. Kept on this Mac, not per server.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(candidates) { candidate in
                Toggle(isOn: binding(for: candidate.key)) {
                    SidebarLabel(title: candidate.title, icon: candidate.icon)
                }
            }
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding {
            ExperimentMainBlock(stored: stored).contains(key)
        } set: { _ in
            var block = ExperimentMainBlock(stored: stored)
            block.toggle(key)
            stored = block.stored
        }
    }
}
#endif
