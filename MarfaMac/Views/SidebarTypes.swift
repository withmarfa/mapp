import SwiftUI

/// The types section: the library's types as one list of rows that fold their subtypes open, at most
/// `SidebarPlan.shownTypeCount` types until Show More. While the sidebar is being customized it lists the top-level
/// types alone, each with a handle, and they drag to reorder; the section's menu shows or hides them.
struct SidebarTypesSection: View, Equatable {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @AppStorage(SidebarTypeRow.subtypeIconsKey) private var showsSubtypeIcons = false
    /// Every shown row, folded open as the person left them.
    let rows: [SidebarPlan.TypeRow]
    let plan: SidebarPlan
    let showsAll: Bool
    let customizing: Bool
    let folding: SidebarFolding
    let browser: Browser
    @Binding var choosingIcon: TypeIconRequest?
    let header: SidebarGroupHeader

    /// The section's data and nothing else, so a change of selection does not run its body. `folding` and the plan it
    /// holds are worked out from the same layout and types, which are compared; the closures and the binding are not.
    static func == (a: Self, b: Self) -> Bool {
        a.rows == b.rows && a.showsAll == b.showsAll && a.customizing == b.customizing && a.header == b.header
            && a.plan.types == b.plan.types && a.plan.layout == b.plan.layout && a.folding.order == b.folding.order
    }

    var body: some View {
        let _ = Cost.record(.sidebarBody, since: .now)
        Section {
            if customizing {
                customizingRows
            } else {
                typeRows
            }
        } header: {
            header.overlay(alignment: .topLeading) { LibraryFillMarker() }
        }
    }

    @ViewBuilder private var typeRows: some View {
        let limited = SidebarPlan.limited(rows, showsAll: showsAll)
        let rows = limited.rows
        let steps = SidebarTypeRow.steps(for: rows, subtypeIcons: showsSubtypeIcons)
        let widest = rows.filter(\.isExpandable).map(\.node.count).max() ?? 0
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            typeRow(row, widestFoldingCount: widest, steps: steps[index])
        }
        if limited.hasMore { showMoreRow }
    }

    /// The top-level types, in the person's order, each draggable.
    private var customizingRows: some View {
        let shown = plan.shownTypes
        return ForEach(shown) { node in
            HStack {
                SidebarLabel(title: node.label, icon: .type(node.icon))
                Spacer(minLength: 8)
                SidebarHandle()
            }
            .selectionDisabled()
            .contextMenu {
                SidebarHideButtons(place: .type(node.id))
                Divider()
                SidebarCustomizeButton(browser: browser)
            }
            .accessibilityIdentifier("SidebarType-\(node.id)")
        }
        .onMove { source, destination in
            libraries.updateSidebarLayout {
                $0.move(plan.types, shown: shown, by: { SidebarPlace.type($0.id).key }, fromOffsets: source, toOffset: destination)
            }
        }
    }

    /// A type opens its own items; a type with subtypes also folds them open, and a group only folds. The rows are
    /// one flat list, a subtype's drawn one step in under its parent, because the system's disclosure puts its chevron
    /// at the leading edge and cannot be moved or guided.
    @ViewBuilder private func typeRow(_ row: SidebarPlan.TypeRow, widestFoldingCount: Int, steps: [SidebarTypeRow.Step]) -> some View {
        let node = row.node
        let content = SidebarTypeRow(
            row: row, count: row.node.count, widestFoldingCount: widestFoldingCount, steps: steps,
            showsIcon: SidebarTypeRow.showsIcon(row, subtypeIcons: showsSubtypeIcons), toggle: { toggle(row) })
        if node.opens, let type = node.type {
            content
                .tag(SidebarItem.itemType(type.rawValue))
                .listRowInsets(.vertical, 0)
                .contextMenu { typeMenu(node) }
                .accessibilityIdentifier("SidebarType-\(node.id)")
        } else {
            // A group only folds, so a click anywhere on its row does.
            Button { toggle(row) } label: {
                content.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .selectionDisabled()
            .listRowInsets(.vertical, 0)
            .contextMenu { typeMenu(node) }
            .accessibilityLabel(Text(node.label))
            .accessibilityValue(row.isExpanded ? Text("Expanded") : Text("Collapsed"))
            .accessibilityIdentifier("SidebarTypeGroup-\(node.id)")
        }
    }

    /// A row of text under the types, starting where the marks of the type rows above it do. A mark sits a little
    /// inside the list's own leading content edge, measured from the sidebar's screenshot.
    private var showMoreRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { browser.sidebarShowsAllTypes.toggle() }
        } label: {
            Group {
                if showsAll { Text("Show Less") } else { Text("Show More") }
            }
            .interfaceFont(.body)
            .foregroundStyle(.secondary)
            .padding(.leading, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .accessibilityIdentifier(showsAll ? "SidebarShowLess" : "SidebarShowMore")
    }

    /// A type's own icon is chosen from its row; a group has no type of its own, so it only hides.
    @ViewBuilder private func typeMenu(_ node: TypeNode) -> some View {
        if let type = node.type {
            Button("Choose Icon…") { choosingIcon = TypeIconRequest(type: type) }
                .disabled(!library.reachesServer)
            Divider()
        }
        SidebarHideButtons(place: .type(node.id))
    }

    private func toggle(_ row: SidebarPlan.TypeRow) {
        folding.setCollapsed(row.node.id, row.isExpanded)
    }
}

/// Folding the type rows, by a click on a row or an arrow key.
struct SidebarFolding {
    let library: any ItemLibrary
    let libraries: Libraries
    let browser: Browser
    let order: ItemOrder
    /// The plan the list was drawn from, so a fold or a key works on the rows the person sees.
    let plan: SidebarPlan

    /// Folding a row that holds the selected type selects the row, so something stays highlighted.
    func setCollapsed(_ id: String, _ collapsed: Bool) {
        if collapsed {
            if let item = plan.selectionAfterFolding(id, selected: browser.sidebarItem) {
                browser.show(item, in: library, order: order)
            }
        }
        withAnimation(.snappy(duration: 0.2)) {
            libraries.updateSidebarLayout { $0.setCollapsed(.type(id), collapsed) }
        }
    }

    /// An arrow key does what the system's outline does for the selected type, and a key with a
    /// modifier belongs to someone else.
    func press(_ arrow: SidebarPlan.Arrow, _ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty else { return .ignored }
        switch plan.outcome(of: arrow, selected: browser.sidebarItem) {
        case .fold(let id, let collapsed): setCollapsed(id, collapsed)
        case .select(let item): browser.show(item, in: library, order: order)
        case nil: return .ignored
        }
        return .handled
    }
}

/// The foot is a bar on the list's edge, so it is not a row of the outline. The measure asks that outline, which stays
/// small on a large library, whether the copy is still filling. This is that answer, and only while it is.
private struct LibraryFillMarker: View {
    @Environment(MarfaHost.self) private var host: MarfaHost?

    var body: some View {
        if let host, FillWording.shows(host.report.fill, in: host.state) {
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityIdentifier("LibraryFillProgress")
        }
    }
}
