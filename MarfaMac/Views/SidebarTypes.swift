import SwiftUI

/// The types section: the library's types as one list of rows that fold their kinds open, at most
/// `SidebarPlan.shownTypeCount` types until the "N More" row. While the sidebar is being customized it lists the
/// top-level types alone, each with a handle, and they drag to reorder; the Type place shows one again.
struct SidebarTypesSection: View, Equatable {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @AppStorage(SidebarTypeRow.subtypeIconsKey) private var showsSubtypeIcons = true
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    /// Every shown row, folded open as the person left them.
    let rows: [SidebarPlan.TypeRow]
    let plan: SidebarPlan
    let showsAll: Bool
    /// The type the window shows, which keeps its row when it is past "N More".
    let open: TypeID?
    let customizing: Bool
    /// The types a plus under the pointer can make an item of.
    let creatable: Set<String>
    let folding: SidebarFolding
    let browser: Browser
    @Binding var choosingIcon: TypeIconRequest?
    let header: SidebarGroupHeader
    let place: SidebarAddPlace

    /// The section's data and nothing else, so a change of selection does not run its body. `folding` and the plan it
    /// holds are worked out from the same layout and types, which are compared; the closures and the binding are not.
    static func == (a: Self, b: Self) -> Bool {
        a.rows == b.rows && a.showsAll == b.showsAll && a.open == b.open && a.customizing == b.customizing && a.header == b.header
            && a.plan.types == b.plan.types && a.plan.layout == b.plan.layout && a.folding.order == b.folding.order
            && a.creatable == b.creatable && a.place.offers == b.place.offers
    }

    var body: some View {
        let _ = Cost.record(.sidebarBody, since: .now)
        // A section never folds, so a press on the heading's menu cannot fold it.
        Section {
            if customizing {
                customizingRows
                place
            } else {
                typeRows
            }
        } header: {
            header
        }
        .collapsible(false)
    }

    @ViewBuilder private var typeRows: some View {
        let limited = SidebarPlan.limited(rows, showsAll: showsAll, open: open)
        let rows = limited.rows
        let steps = SidebarTypeRow.steps(for: rows, subtypeIcons: showsSubtypeIcons)
        let widest = rows.filter(\.isExpandable).map(\.node.count).max() ?? 0
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            typeRow(row, widestFoldingCount: widest, steps: steps[index])
        }
        if limited.more > 0 { moreRow(limited.more) }
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
                Button("Remove from Sidebar") { libraries.updateSidebarLayout { $0.take(.type(node.id)) } }
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
            showsIcon: SidebarTypeRow.showsIcon(row, subtypeIcons: showsSubtypeIcons), add: add(node), addName: addName(node),
            toggle: { toggle(row) })
        if node.opens, let type = node.type {
            content
                .tag(PlaceView.type(type))
                .listRowInsets(.vertical, 0)
                .contextMenu { typeMenu(node) }
                .accessibilityIdentifier("SidebarType-\(node.id)")
        } else {
            // A group only folds, so a click anywhere on its row does. A tap, not a button, so the row's ground under
            // the pointer reaches the list.
            content
                .contentShape(.rect)
                .onTapGesture { toggle(row) }
                .selectionDisabled()
                .listRowInsets(.vertical, 0)
                .contextMenu { typeMenu(node) }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggle(row) }
                .accessibilityLabel(Text(node.label))
                .accessibilityValue(row.isExpanded ? Text("Expanded") : Text("Collapsed"))
                .accessibilityIdentifier("SidebarTypeGroup-\(node.id)")
        }
    }

    /// "N More" under the types, in gray, starting where the names of the rows above do; "Show Less" once they show.
    private func moreRow(_ more: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { browser.sidebarShowsAllTypes.toggle() }
        } label: {
            Label {
                Group {
                    if showsAll { Text("Show Less") } else { Text("\(more) More") }
                }
                .interfaceFont(.body)
                .foregroundStyle(.secondary)
            } icon: {
                TonedGlyph(id: nil).hidden()
            }
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
        Button("Remove from Sidebar") { libraries.updateSidebarLayout { $0.take(.type(node.id)) } }
        Divider()
        SidebarCustomizeButton(browser: browser)
    }

    /// Makes an item of the row's type, where quick add can make one. A kind of file is made by adding a file, as File is.
    private func add(_ node: TypeNode) -> (() -> Void)? {
        guard let type = node.type else { return nil }
        let made = library.catalogue.isFileType(type) ? TypeID.file : type
        guard creatable.contains(made.rawValue) else { return nil }
        return { browser.openQuickAdd(typeID: made.rawValue, in: library) }
    }

    private func addName(_ node: TypeNode) -> String {
        guard let type = node.type else { return "" }
        return String(localized: "New \(library.catalogue.label(for: type))")
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
            if let item = plan.selectionAfterFolding(id, selected: browser.showing) {
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
        switch plan.outcome(of: arrow, selected: browser.showing) {
        case .fold(let id, let collapsed): setCollapsed(id, collapsed)
        case .select(let item): browser.show(item, in: library, order: order)
        case nil: return .ignored
        }
        return .handled
    }
}
