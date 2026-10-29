import SwiftUI

/// The Types block: its heading with Edit on hover, and the library's types as one list of rows that fold their
/// subtypes open, at most `SidebarPlan.shownTypeCount` types until Show More.
struct SidebarTypesSection: View {
    @CurrentLibrary private var library
    @AppStorage(SidebarTypeRow.subtypeIconsKey) private var showsSubtypeIcons = false
    @State private var editsTypes = false
    let plan: SidebarPlan
    let folding: SidebarFolding
    @Binding var showsAll: Bool
    @Binding var choosingIcon: TypeIconRequest?

    var body: some View {
        let _ = Cost.record(.sidebarBody, since: .now)
        let limited = SidebarPlan.limited(plan.typeRows, showsAll: showsAll)
        let rows = limited.rows
        let steps = SidebarTypeRow.steps(for: rows, subtypeIcons: showsSubtypeIcons)
        let widest = rows.filter(\.isExpandable).map(count(of:)).max() ?? 0
        Section {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                typeRow(row, widestFoldingCount: widest, steps: steps[index])
            }
            if limited.hasMore { showMoreRow }
        } header: {
            TypesHeading(editsTypes: $editsTypes)
        }
    }

    /// A type opens its own items; a type with subtypes also folds them open, and a group only folds. The rows are
    /// one flat list, a subtype's drawn one step in under its parent, because the system's disclosure puts its chevron
    /// at the leading edge and cannot be moved or guided.
    @ViewBuilder private func typeRow(_ row: SidebarPlan.TypeRow, widestFoldingCount: Int, steps: [SidebarTypeRow.Step]) -> some View {
        let node = row.node
        let content = SidebarTypeRow(
            row: row, count: count(of: row), widestFoldingCount: widestFoldingCount, steps: steps,
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
            withAnimation(.snappy(duration: 0.2)) { showsAll.toggle() }
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
                .disabled(!library.canChooseTypeIcons)
            Divider()
        }
        SidebarHideButtons(place: .type(node.id))
    }

    private func count(of row: SidebarPlan.TypeRow) -> Int {
        guard row.node.opens, let type = row.node.type else { return 0 }
        return library.count(in: .itemType(type.rawValue))
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
    let order: NoteOrder

    /// Folding a row that holds the selected type selects the row, so something stays highlighted.
    func setCollapsed(_ id: String, _ collapsed: Bool) {
        if collapsed, !browser.showsSettings {
            let plan = SidebarPlan(library, layout: libraries.sidebarLayout)
            if let item = plan.selectionAfterFolding(id, selected: browser.sidebarItem) {
                browser.show(item, in: library, order: order)
            }
        }
        withAnimation(.snappy(duration: 0.2)) {
            libraries.updateSidebarLayout { $0.setCollapsed(.type(id), collapsed) }
        }
    }

    /// An arrow key does what the system's outline does for the selected type. Settings shows no selection, and a
    /// key with a modifier belongs to someone else.
    func press(_ arrow: SidebarPlan.Arrow, _ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty, !browser.showsSettings else { return .ignored }
        let plan = SidebarPlan(library, layout: libraries.sidebarLayout)
        switch plan.outcome(of: arrow, selected: browser.sidebarItem) {
        case .fold(let id, let collapsed): setCollapsed(id, collapsed)
        case .select(let item): browser.show(item, in: library, order: order)
        case nil: return .ignored
        }
        return .handled
    }
}

/// The Types heading. Edit shows only while the pointer is over the heading, or its picker is open, as the control
/// of a sidebar's section heading does.
struct TypesHeading: View {
    @Binding var editsTypes: Bool
    @State private var isHovering = false

    var body: some View {
        HStack {
            Text("Types")
            Spacer()
            Button("Edit") { editsTypes = true }
                .buttonStyle(.plain)
                .opacity(isHovering || editsTypes ? 1 : 0)
                .popover(isPresented: $editsTypes) {
                    SidebarTypePicker()
                }
                .accessibilityIdentifier("EditSidebarTypes")
        }
        .padding(.trailing, 12)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("SidebarTypes")
    }
}
