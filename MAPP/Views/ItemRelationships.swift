import MarfaIcons
import SwiftUI

/// A relationship as a group of the inspector: its name as a small heading above a box of its own, each item it reaches
/// as a light row in the box with the item's type icon, which opens it, and a small plus in the trailing column at its name where the relationship
/// takes several. An editable one offers Open, Change or Manage, and Remove from a menu that shows on hover and in the
/// context menu.
struct ItemRelationshipGroup: View {
    let relationship: ItemRelationship
    /// The icon of the type of the item a target points at.
    var typeIcon: (ItemID) -> String? = { _ in nil }
    /// Whether the person has shown every link of the group, and what shows them.
    var isExpanded = false
    var onShowAll: () -> Void = {}
    let onOpen: (ItemID) -> Void
    let onEdit: () -> Void
    let onRemove: (ItemID) async -> Bool
    /// Whether the page shows this relationship too, and what changes it; nil offers no choice.
    var shownOnPage = true
    var onShowOnPage: ((Bool) -> Void)?
    @State private var rejected = false
    @State private var hovering = false

    /// The heading sits above a box of its own, so each relationship reads as a group. The box takes the links, the
    /// rest of them and a refusal as rows, never one row holding them.
    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            HStack(spacing: 4) {
                InspectorSubheading(title: relationship.label, count: relationship.targets.count)
                Spacer(minLength: 0)
                if relationship.isEditable && relationship.allowsMultiple {
                    InspectorPlusButton(
                        accessibilityLabel: "Add to \(relationship.label)",
                        identifier: "RelationshipAddRow.\(relationship.field)", isRowHovered: hovering, action: onEdit)
                        .inspectorTrailingColumn(clearsFold: false)
                }
            }
            .padding(.horizontal, InspectorMetrics.boxInset)
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .showOnPageMenu(isShown: shownOnPage, onChange: onShowOnPage)
            let links = LinkLimit.split(relationship.targets, expanded: isExpanded)
            InspectorBox {
                ForEach(links.shown) { target in
                    ItemTargetRow(target: target, relationship: relationship, typeIcon: typeIcon, onOpen: onOpen, onEdit: onEdit) { id in
                        Task { rejected = !(await onRemove(id)) }
                    }
                    .showOnPageMenu(isShown: shownOnPage, onChange: onShowOnPage)
                }
                if links.hidden > 0 {
                    ItemShowMoreButton(count: links.hidden, identifier: "RelationshipShowMore.\(relationship.field)", action: onShowAll)
                }
                if rejected {
                    Text("The connection could not be removed.")
                        .interfaceFont(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}

/// The small heading of a group inside a section: the name of a relationship.
struct InspectorSubheading: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: title)
            if let count {
                Text(count, format: .number).monospacedDigit()
            }
        }
        .interfaceFont(.callout.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One item a relationship reaches, as a row across the width: the type's icon and the title, which opens the item.
/// Where a relationship can be changed, the row shows a menu while the pointer is over it.
struct ItemTargetRow: View {
    let target: ItemRelationshipTarget
    let relationship: ItemRelationship
    var typeIcon: (ItemID) -> String? = { _ in nil }
    let onOpen: (ItemID) -> Void
    let onEdit: () -> Void
    let onRemove: (ItemID) -> Void
    @Environment(\.interfaceTextSize) private var textSize
    @State private var hovering = false

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let shows = relationship.isEditable && hovering
        InspectorItemRow(target: target, typeIcon: typeIcon, onOpen: onOpen,
                         trailingInset: shows ? InspectorMetrics.trailingColumn * scale : 0)
            .overlay(alignment: .trailing) {
                if shows { actions.inspectorTrailingColumn(clearsFold: false) }
            }
            .onHover { hovering = $0 }
            .contextMenu { menuItems }
    }

    private var actions: some View {
        Menu {
            menuItems
        } label: {
            Label("Connection Actions", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .frame(width: InspectorMetrics.trailingColumn * InterfaceStyle.scale(for: textSize),
                       height: InspectorMetrics.trailingColumn * InterfaceStyle.scale(for: textSize))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Connection Actions")
        .accessibilityIdentifier("RelationshipActions.\(relationship.field).\(target.id)")
    }

    @ViewBuilder private var menuItems: some View {
        if let id = target.itemID, target.isOpenable {
            Button("Open Item") { onOpen(id) }
        }
        if relationship.isEditable {
            Button(relationship.allowsMultiple ? "Manage Connections…" : "Replace…", action: onEdit)
                .accessibilityIdentifier("RelationshipEdit.\(relationship.field)")
            if let id = target.itemID {
                Button("Remove Connection", role: .destructive) { onRemove(id) }
            }
        }
    }
}

extension VerticalAlignment {
    /// The center of a link row's title, which its mark sits on, whatever stands under the title.
    static let inspectorTitleCenter = VerticalAlignment(InspectorTitleCenter.self)
}

private enum InspectorTitleCenter: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
}

/// The control that ends a group of links cut short: it shows the rest.
struct ItemShowMoreButton: View {
    let count: Int
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Show \(count) More")
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(InspectorRowButtonStyle())
        .accessibilityIdentifier(identifier)
    }
}

/// An item as a light row across the width, with its type's icon. A link to an item the library does not hold, or
/// that cannot be opened, says why instead.
struct InspectorItemRow: View {
    let target: ItemRelationshipTarget
    var typeIcon: (ItemID) -> String? = { _ in nil }
    let onOpen: (ItemID) -> Void
    /// Room kept at the end of the row for a control laid over it.
    var trailingInset: CGFloat = 0

    var body: some View {
        Group {
            if let id = target.itemID, target.isOpenable {
                Button { onOpen(id) } label: {
                    HStack(alignment: .inspectorTitleCenter, spacing: InspectorMetrics.markGap) {
                        TypeMark(icon: typeIcon(id), size: .row)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.displayTitle)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .multilineTextAlignment(.leading)
                                .alignmentGuide(.inspectorTitleCenter) { $0[VerticalAlignment.center] }
                            if target.isDeleted {
                                Label("Deleted", systemImage: "trash")
                                    .interfaceFont(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, trailingInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(InspectorRowButtonStyle())
                .foregroundStyle(.primary)
                .help(target.displayTitle)
                .accessibilityIdentifier("RelationshipTarget.\(id.rawValue)")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    // A link to an item the library does not hold has no title to show.
                    if !target.title.isEmpty {
                        Text(target.title).lineLimit(2)
                    }
                    Label(resolutionLabel, systemImage: "exclamationmark.triangle")
                        .interfaceFont(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .interfaceFont(.body)
    }

    private var resolutionLabel: String {
        switch target.resolution {
        case .ambiguous: String(localized: "More than one item matches")
        case .missing: String(localized: "Item not found")
        case .pending: String(localized: "Not looked up yet")
        case .refused: String(localized: "The server refused this link")
        case .resolved: String(localized: "Item unavailable")
        }
    }
}

/// Changes are committed together; dismissing the chooser leaves existing connections intact.
struct ItemRelationshipPicker: View {
    @CurrentLibrary private var library
    /// The item whose relationship is chosen, which each candidate is checked against.
    let owner: ItemID
    let relationship: ItemRelationship
    let candidates: [Item]
    /// What the person changed from the items linked when the picker opened: the items to link and to unlink.
    /// Whether the library accepted the change, answered once it has judged it. The library applies it to the links it
    /// holds then, so a change made while the picker was open is kept.
    let onSave: (_ adding: [ItemID], _ removing: [ItemID]) async -> Bool
    /// The items linked when the picker opened, which the selection is compared with.
    private let opened: Set<ItemID>
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: Set<ItemID>
    @State private var rejected = false
    /// While the library judges the selection, so a second Save does not send it again.
    @State private var saving = false

    init(owner: ItemID, relationship: ItemRelationship, candidates: [Item], onSave: @escaping ([ItemID], [ItemID]) async -> Bool) {
        self.owner = owner
        self.relationship = relationship
        self.candidates = candidates
        self.onSave = onSave
        opened = Set(relationship.targets.compactMap(\.itemID))
        _selection = State(initialValue: opened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(relationship.label)).interfaceFont(.title2.bold())
            TextField("Search Items", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("RelationshipSearch")
            List(filtered) { candidate in
                RelationshipCandidateRow(
                    owner: owner, field: relationship.field, candidate: candidate,
                    isLinked: relationship.targets.contains { $0.itemID == candidate.id },
                    isSelected: selection.contains(candidate.id)
                ) {
                    if selection.contains(candidate.id) {
                        selection.remove(candidate.id)
                    } else if relationship.allowsMultiple {
                        selection.insert(candidate.id)
                    } else {
                        selection = [candidate.id]
                    }
                }
            }
            .overlay {
                if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            }
            if relationship.targets.contains(where: { $0.itemID == nil }) {
                Text("Unresolved connections will be preserved.")
                    .interfaceFont(.caption).foregroundStyle(.secondary)
            }
            if rejected {
                Text("The connections could not be saved. Your selection has been kept.")
                    .interfaceFont(.callout).foregroundStyle(.red)
            }
            HStack {
                Button("Clear Selection") { selection = [] }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    let adding = selection.subtracting(opened).sorted { $0.rawValue < $1.rawValue }
                    let removing = opened.subtracting(selection).sorted { $0.rawValue < $1.rawValue }
                    saving = true
                    Task {
                        if await onSave(adding, removing) { dismiss() } else { rejected = true }
                        saving = false
                    }
                }
                .disabled(saving)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("RelationshipSave")
            }
        }
        .padding(20)
        .frame(width: 440, height: 460)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RelationshipPicker")
    }

    private var filtered: [Item] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? candidates : candidates.filter { $0.title.localizedStandardContains(query) }
    }
}

#if DEBUG
#Preview("Wrapping Connections") {
    let id = ItemID("10000000-0000-0000-0000-000000000001")
    let names = SampleLibrary.catalogue.edgeTypes
    let parent = ItemRelationship(
        field: "child-of", label: names["parent-of"]?.reverseLabel ?? "", targets: [
            .init(title: "Field Research: review the observations and photographs from every location", itemID: id, resolution: .resolved(id))
        ], isEditable: true, allowsMultiple: false)
    let about = ItemRelationship(
        field: "about", label: names["about"]?.label ?? "", targets: [
            .init(title: "Field notes", itemID: id, resolution: .resolved(id)),
            .init(title: "Interview with the site manager", itemID: nil, resolution: .missing)
        ], isEditable: true, allowsMultiple: true)
    VStack(alignment: .leading, spacing: InspectorMetrics.groupGap) {
        ItemRelationshipGroup(relationship: parent, onOpen: { _ in }, onEdit: {}, onRemove: { _ in true })
        ItemRelationshipGroup(relationship: about, onOpen: { _ in }, onEdit: {}, onRemove: { _ in true })
    }
    .padding(16)
    .interfaceTextStyle()
    .frame(width: 300)
}
#endif

/// One item a relationship could link to. Whether the core would take the link is asked of it when the row appears,
/// so a picker of many items asks only of those scrolled to; a link the core refuses is dimmed, with why.
private struct RelationshipCandidateRow: View {
    @CurrentLibrary private var library
    let owner: ItemID
    let field: String
    let candidate: Item
    /// Already linked, so not asked: the core judges new edges.
    let isLinked: Bool
    let isSelected: Bool
    let choose: () -> Void
    @State private var refusal: String?

    /// A check that could not be made (the copy not whole yet, the key changing) is asked again after a pause that
    /// doubles, up to six times; only the core's own refusal disables the row.
    private func check() async {
        refusal = nil
        guard !isLinked else { return }
        var pause = Duration.seconds(1)
        for _ in 0..<6 {
            switch await library.relationshipVerdict(for: owner, field: field, to: candidate.id) {
            case .refused(let message): return refusal = message
            case .taken: return
            case .unknown:
                try? await Task.sleep(for: pause)
                if Task.isCancelled { return }
                pause *= 2
            }
        }
    }

    var body: some View {
        Button(action: choose) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading) {
                    Text(candidate.displayTitle)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LocalizedStringKey(library.catalogue.itemTypes[candidate.type]?.label ?? candidate.type.rawValue))
                        .interfaceFont(.caption).foregroundStyle(.secondary)
                    if let refusal {
                        Text(verbatim: refusal).interfaceFont(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(refusal != nil)
        .task(id: candidate.id) { await check() }
        .accessibilityIdentifier("RelationshipCandidate.\(candidate.id.rawValue)")
        .accessibilityValue(isSelected ? "Selected" : "Not Selected")
    }
}
