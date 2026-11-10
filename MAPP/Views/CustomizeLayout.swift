import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Customize Layout in the menu bar, the toolbar's More menu and the context menu: starts arranging the page of the one
/// item selected, in the window whose presentation it is given. While the mode is on it finishes it, as the toolbar's
/// Done does, for a window with its toolbar hidden.
struct CustomizeLayoutButton: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    let details: DetailsPresentation?

    var body: some View {
        if details?.isCustomizingLayout == true {
            Button("Finish Customizing", systemImage: "slider.horizontal.3") { details?.endLayout() }
        } else {
            Button("Customize Layout…", systemImage: "slider.horizontal.3") { details?.beginLayout() }
                .disabled(ids.count != 1 || details?.canBeginLayout(for: ids.first.flatMap { library.item($0) }) != true)
        }
    }
}

/// What a dragged row carries inside the app: its identifier, which is all a drop on a group reads.
nonisolated struct LayoutRowDrag: Codable, Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mappLayoutRow)
    }
}

extension UTType {
    /// Named for the bundle identifier, as `MAPP/Info.plist` declares it, so a row never drags into the other build.
    nonisolated static let mappLayoutRow = UTType(exportedAs: "\(Bundle.main.bundleIdentifier ?? "com.withmarfa.mapp").layout-row")
}

/// The right sidebar while Customize Layout is on. Page arranges the item's rows in three groups, Pinned (up to four), On
/// the Page and Hidden, by dragging, by the pin on a row, or with Move Up and Move Down; Sidebar orders, removes and adds
/// the sidebar's own sections (`SidebarArrangement`). The page and the sidebar stay in view and follow each change at
/// once. Both choices are for the item's type (`PagePlacements`), so they hold for every item of the type, and they are
/// MAPP's own: the item is not changed, so a read-only item can be laid out too.
struct ItemLayoutPanel: View {
    private enum Arranging: Hashable { case page, sidebar }

    @CurrentLibrary private var library
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()
    @State private var arranging = Arranging.page
    let item: Item

    var body: some View {
        VStack(spacing: 0) {
            Picker("Arrange", selection: $arranging) {
                Text("Page").tag(Arranging.page)
                Text("Sidebar").tag(Arranging.sidebar)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .buttonSizing(.flexible)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .accessibilityIdentifier("LayoutArranging")
            ScrollView {
                switch arranging {
                case .page: pageGroups
                case .sidebar: SidebarArrangement(item: item)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ItemLayoutPanel")
    }

    private var pageGroups: some View {
        let layout = self.layout
        return VStack(alignment: .leading, spacing: InspectorMetrics.sectionGap) {
            LayoutGroupView(group: .pinned, layout: layout, options: { options }, change: apply)
            LayoutGroupView(group: .page, layout: layout, options: { EmptyView() }, change: apply)
            LayoutGroupView(group: .hidden, layout: layout, options: { EmptyView() }, change: apply)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var layout: PageLayout {
        let rows = PageLayout.rows(
            of: item, type: library.catalogue.itemTypes[item.type], hidden: library.hiddenPropertyKeys(of: item),
            relationships: library.relationships(for: item.id), catalogue: library.catalogue)
        return PageLayout(rows: rows, placement: placements.placement(of: item.type, in: library.catalogue))
    }

    private func apply(_ layout: PageLayout) {
        placements.apply(layout, of: item.type, in: library.catalogue)
    }

    /// Takes the type's choices back, for the page and the sidebar, quietly, beside the first heading.
    private var options: some View {
        Menu {
            Button("Use Defaults") { placements.reset(item.type) }
                .disabled(!placements.hasChoice(for: item.type))
                .accessibilityIdentifier("LayoutUseDefaults")
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Layout Options")
        .accessibilityLabel("Layout Options")
        .accessibilityIdentifier("LayoutOptions")
    }
}

/// One group of the layout: its heading with the count, and its rows in a box.
private struct LayoutGroupView<Options: View>: View {
    let group: PageLayout.Group
    let layout: PageLayout
    @ViewBuilder let options: () -> Options
    let change: (PageLayout) -> Void
    @State private var isTargeted = false

    var body: some View {
        let rows = layout.rows(in: group)
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(title)
                    Text(count).fontWeight(.regular).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                options()
            }
            .interfaceFont(.body.weight(.semibold))
            .padding(.horizontal, InspectorMetrics.headingInset)
            InspectorBox {
                if rows.isEmpty {
                    Text(placeholder).foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        LayoutRowView(row: row, group: group, layout: layout, change: change)
                    }
                }
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: InspectorMetrics.boxRadius, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .dropDestination(for: LayoutRowDrag.self) { drops, _ in
                guard let drop = drops.first, let moved = layout.moving(drop.id, to: group) else { return false }
                change(moved)
                return true
            } isTargeted: { isTargeted = $0 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var title: LocalizedStringKey {
        switch group {
        case .pinned: "Pinned"
        case .page: "On the Page"
        case .hidden: "Hidden"
        }
    }

    /// Pinned says how many of the most it holds, the others how many rows they hold.
    private var count: String {
        let rows = layout.rows(in: group).count
        return group == .pinned ? String(localized: "\(rows) of \(PagePlacement.pinLimit)") : rows.formatted()
    }

    private var placeholder: LocalizedStringKey {
        switch group {
        case .pinned: "Nothing Pinned"
        case .page: "Nothing on the Page"
        case .hidden: "Nothing Hidden"
        }
    }

    private var identifier: String {
        switch group {
        case .pinned: "LayoutPinned"
        case .page: "LayoutOnPage"
        case .hidden: "LayoutHidden"
        }
    }
}

/// A row of a group: a grip, the symbol of its kind of value, its name, and the pin. Dragging it, the pin, and Move Up
/// and Move Down (in its menu, as accessibility actions, and with Option and the arrow keys) place it.
private struct LayoutRowView: View {
    @Environment(\.interfaceTextSize) private var textSize
    let row: PageLayout.Row
    let group: PageLayout.Group
    let layout: PageLayout
    let change: (PageLayout) -> Void

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: InspectorMetrics.gap) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11 * scale))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Image(systemName: row.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18 * scale)
                .accessibilityHidden(true)
            Text(verbatim: row.label)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            pin
        }
        .interfaceFont(.body)
        .contentShape(.rect)
        .help(row.label)
        .draggable(LayoutRowDrag(id: row.id))
        // A drop on a row takes that row's place in its group.
        .dropDestination(for: LayoutRowDrag.self) { drops, _ in
            guard let drop = drops.first, drop.id != row.id,
                  let index = layout.rows(in: group).firstIndex(where: { $0.id == row.id }),
                  let moved = layout.moving(drop.id, to: group, at: index)
            else { return false }
            change(moved)
            return true
        }
        .focusable()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers == .option, let moved = layout.moved(row.id, by: press.key == .upArrow ? -1 : 1) else { return .ignored }
            change(moved)
            return .handled
        }
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.label)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("LayoutRow.\(row.id)")
        .accessibilityActions { actions }
    }

    /// The pin: filled while the row is pinned, and dimmed while four are. Linked From cannot be pinned, so it has none.
    @ViewBuilder private var pin: some View {
        let pinned = group == .pinned
        if row.id != PagePlacement.linkedFrom {
            Button {
                if let moved = layout.moving(row.id, to: pinned ? .page : .pinned) { change(moved) }
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .foregroundStyle(pinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .frame(width: InspectorMetrics.trailingColumn, height: InspectorMetrics.trailingColumn)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!pinned && !layout.canPin)
            .help(help)
            .accessibilityLabel(pinned ? "Unpin" : "Pin")
            .accessibilityIdentifier("LayoutPin.\(row.id)")
        }
    }

    private var help: LocalizedStringKey {
        if group == .pinned { return "Unpin" }
        return layout.canPin ? "Pin" : "Four Pins at Most"
    }

    private var accessibilityValue: Text {
        switch group {
        case .pinned: Text("Pinned")
        case .page: Text("On the Page")
        case .hidden: Text("Hidden")
        }
    }

    /// Every way to place the row without the pointer.
    @ViewBuilder private var actions: some View {
        Button("Move Up") { if let moved = layout.moved(row.id, by: -1) { change(moved) } }
            .disabled(layout.moved(row.id, by: -1) == nil)
        Button("Move Down") { if let moved = layout.moved(row.id, by: 1) { change(moved) } }
            .disabled(layout.moved(row.id, by: 1) == nil)
        if row.id != PagePlacement.linkedFrom {
            if group == .pinned {
                Button("Unpin") { if let moved = layout.moving(row.id, to: .page) { change(moved) } }
            } else {
                Button("Pin") { if let moved = layout.moving(row.id, to: .pinned) { change(moved) } }
                    .disabled(!layout.canPin)
            }
        }
        if group == .hidden {
            Button("Show on Page") { if let moved = layout.moving(row.id, to: .page) { change(moved) } }
        } else {
            Button("Hide from Page") { if let moved = layout.moving(row.id, to: .hidden) { change(moved) } }
        }
    }
}
