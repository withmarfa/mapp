import SwiftUI

/// Sidebar, the second half of Customize Layout: the right sidebar's sections for the item's type, each a row with a
/// handle, its name and count, and a button that removes it. Rows are ordered by dragging or with Move Up and Move Down.
/// Add Section lists the sections not shown, and sections an app's data gives the type under From Apps. The sidebar beside
/// the panel follows each change at once. A section an item has nothing for stays hidden on that item but keeps its place
/// in the arrangement.
struct SidebarArrangement: View {
    @CurrentLibrary private var library
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    let item: Item
    /// The headings the page reported for the item.
    var outline: [OutlineHeading] = []

    /// What this reads is read once for a change to the library or the arrangement: the drag and the open panel keep their
    /// state in the views below, so hovering a drag or opening Add Section reads nothing again.
    var body: some View {
        let relationships = library.relationships(for: item.id)
        let shown = placements.sidebarSections(of: item.type, in: library.catalogue).compactMap(SidebarSection.init(id:))
        // The app sections are read once, apart from the rest: they give both the counts and what Add Section offers,
        // including groups not shown. Attachments and collections are read only where a shown section needs them.
        let extras = SidebarExtras.of(item, in: library, relationships: relationships, sections: shown, outline: outline)
        let apps = SidebarExtras.appSections(of: item, in: library, relationships: relationships)
        VStack(alignment: .leading, spacing: InspectorMetrics.groupGap) {
            SectionsBox(
                shown: shown, names: Dictionary(shown.map { ($0.id, title(of: $0)) }, uniquingKeysWith: { first, _ in first }),
                counts: Dictionary(
                    shown.compactMap { section in count(of: section, relationships: relationships, extras: extras, apps: apps).map { (section.id, $0) } },
                    uniquingKeysWith: { first, _ in first }),
                move: move, remove: remove, reset: reset, hasChoice: placements.hasChoice(for: item.type))
            AddSectionControl(
                typeName: library.catalogue.label(for: item.type),
                builtIn: SidebarSection.builtIn.filter { !shown.contains($0) },
                apps: apps.filter { !shown.contains($0.section) },
                choose: { placements.addSidebarSection($0.id, of: item.type, in: library.catalogue) })
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(of section: SidebarSection) -> String {
        section.title(in: library.catalogue, sources: library.sources)
    }

    /// How many rows a section holds for this item, which the row names beside the section. Nil for Details, and for
    /// a section the item has none of, which says nothing.
    private func count(of section: SidebarSection, relationships: [ItemRelationship], extras: SidebarExtras, apps: [AppSection]) -> Int? {
        let count: Int? = switch section {
        case .details: nil
        case .properties:
            InspectorFields.properties(
                of: item, type: library.catalogue.itemTypes[item.type], hidden: library.hiddenPropertyKeys(of: item)).count
        case .relationships: InspectorFields.relationships(relationships).reduce(0) { $0 + $1.targets.count }
        case .linksInPage: library.bodyMentions(for: item.id).count
        case .linkedFrom:
            ItemInspectorHost.linked(to: item, in: relationships, library: library, format: dateFormat).count
        case .tags: library.tags(of: item).count
        case .outline, .attachments, .collections: extras.count(of: section)
        case .app: apps.first { $0.section == section }?.targets.count
        }
        return count.flatMap { $0 > 0 ? $0 : nil }
    }

    private func move(_ id: String, _ index: Int) {
        placements.moveSidebarSection(id, to: index, of: item.type, in: library.catalogue)
    }

    private func remove(_ section: SidebarSection) {
        placements.removeSidebarSection(section.id, of: item.type, in: library.catalogue)
    }

    private func reset() { placements.reset(item.type) }
}

/// The sections shown, as rows in a box that takes a drop beside them.
private struct SectionsBox: View {
    @State private var isTargeted = false
    let shown: [SidebarSection]
    let names: [String: String]
    let counts: [String: Int]
    let move: (String, Int) -> Void
    let remove: (SidebarSection) -> Void
    let reset: () -> Void
    let hasChoice: Bool

    var body: some View {
        InspectorBox {
            if shown.isEmpty {
                Text("No Sections").foregroundStyle(.secondary)
            } else {
                ForEach(shown, id: \.id) { section in
                    SidebarSectionRow(
                        section: section, shown: shown, name: names[section.id] ?? section.title, count: counts[section.id],
                        move: move, remove: { remove(section) }, reset: reset, hasChoice: hasChoice)
                }
            }
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: InspectorMetrics.boxRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        // A drop beside the rows puts the section last.
        .dropDestination(for: LayoutRowDrag.self) { drops, _ in
            guard let drop = drops.first, shown.contains(where: { $0.id == drop.id }) else { return false }
            move(drop.id, shown.count)
            return true
        } isTargeted: { isTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SidebarSections")
    }
}

/// The Add Section button and the panel it opens under it, which keeps its own open state.
private struct AddSectionControl: View {
    @State private var isAdding = false
    let typeName: String
    let builtIn: [SidebarSection]
    let apps: [AppSection]
    let choose: (SidebarSection) -> Void

    var body: some View {
        AddSectionButton(isOpen: $isAdding, isEnabled: !builtIn.isEmpty || !apps.isEmpty)
            .popover(isPresented: $isAdding, arrowEdge: .bottom) {
                AddSectionPanel(typeName: typeName, builtIn: builtIn, apps: apps) { section in
                    choose(section)
                    isAdding = false
                }
            }
    }
}

/// A section of the arrangement: a handle, its name and count, and the remove button. Dragging it, Move Up and Move Down
/// (in its menu, as accessibility actions, and with Option and the arrow keys) and Remove place it.
private struct SidebarSectionRow: View {
    @Environment(\.interfaceTextSize) private var textSize
    let section: SidebarSection
    let shown: [SidebarSection]
    let name: String
    let count: Int?
    let move: (String, Int) -> Void
    let remove: () -> Void
    let reset: () -> Void
    let hasChoice: Bool

    private var index: Int { shown.firstIndex(of: section) ?? 0 }

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: InspectorMetrics.gap) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11 * scale))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                Text(verbatim: name)
                if let count { Text(count, format: .number).monospacedDigit().foregroundStyle(.secondary) }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
            Button(action: remove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: InspectorMetrics.trailingColumn * scale, height: InspectorMetrics.trailingColumn * scale)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Remove from Sidebar")
            .accessibilityLabel("Remove from Sidebar")
            .accessibilityIdentifier("SidebarRemove.\(section.id)")
        }
        .interfaceFont(.body)
        .contentShape(.rect)
        .help(name)
        .draggable(LayoutRowDrag(id: section.id))
        // A drop on a row takes that row's place.
        .dropDestination(for: LayoutRowDrag.self) { drops, _ in
            guard let drop = drops.first, drop.id != section.id, shown.contains(where: { $0.id == drop.id }) else { return false }
            move(drop.id, index)
            return true
        }
        .focusable()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers == .option else { return .ignored }
            let target = index + (press.key == .upArrow ? -1 : 1)
            guard shown.indices.contains(target) else { return .ignored }
            move(section.id, target)
            return .handled
        }
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
        .accessibilityIdentifier("SidebarRow.\(section.id)")
        .accessibilityActions { actions }
    }

    @ViewBuilder private var actions: some View {
        Button("Move Up") { move(section.id, index - 1) }.disabled(index == 0)
        Button("Move Down") { move(section.id, index + 1) }.disabled(index >= shown.count - 1)
        Button("Remove from Sidebar", action: remove)
        Divider()
        Button("Use Defaults", action: reset).disabled(!hasChoice)
    }
}

/// The dashed button under the sections that opens the list of what can be added.
private struct AddSectionButton: View {
    @Binding var isOpen: Bool
    let isEnabled: Bool

    var body: some View {
        Button { isOpen.toggle() } label: {
            Label("Add Section", systemImage: "plus")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: InspectorMetrics.boxRowHeight)
                .background {
                    RoundedRectangle(cornerRadius: InspectorMetrics.boxRadius, style: .continuous)
                        .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .interfaceFont(.body)
        .disabled(!isEnabled)
        .accessibilityIdentifier("SidebarAddSection")
    }
}

/// What Add Section lists: the sections not shown, each with its symbol, and under a divider the groups an app's data
/// gives the item, named for the app. With no group from an app there is no From Apps heading.
private struct AddSectionPanel: View {
    let typeName: String
    let builtIn: [SidebarSection]
    let apps: [AppSection]
    let choose: (SidebarSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sections for \(typeName)")
                .interfaceFont(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            ForEach(builtIn, id: \.id) { section in
                AddSectionRow(title: section.title, trailing: nil) {
                    Image(systemName: section.symbol)
                } action: { choose(section) }
                .accessibilityIdentifier("SidebarAdd.\(section.id)")
            }
            if !apps.isEmpty {
                if !builtIn.isEmpty { Divider().padding(.vertical, 4) }
                Text("From Apps")
                    .interfaceFont(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                ForEach(apps) { app in
                    AddSectionRow(title: app.title, trailing: app.sourceName) {
                        TypeGlyph(id: app.icon)
                    } action: { choose(app.section) }
                    .accessibilityIdentifier("SidebarAdd.\(app.id)")
                }
            }
        }
        .padding(8)
        .frame(minWidth: 240)
    }
}

private struct AddSectionRow<Mark: View>: View {
    @Environment(\.interfaceTextSize) private var textSize
    let title: String
    let trailing: String?
    @ViewBuilder let mark: Mark
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: InspectorMetrics.gap) {
                mark
                    .foregroundStyle(.secondary)
                    .frame(width: 18 * InterfaceStyle.scale(for: textSize))
                    .accessibilityHidden(true)
                Text(verbatim: title).lineLimit(1)
                Spacer(minLength: 12)
                if let trailing { Text(verbatim: trailing).foregroundStyle(.secondary).lineLimit(1) }
            }
            .interfaceFont(.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(InspectorRowButtonStyle())
        .foregroundStyle(.primary)
    }
}
