import SwiftUI

/// A sidebar row's mark and name, laid out as the system lays out its own sidebar labels. A place's mark is a
/// symbol in the system's gray; a type's is its colored `TonedGlyph`, or the same glyph in gray for a collection
/// (`grayType`). Without a mark it is the name alone.
struct SidebarLabel: View {
    let title: String
    let icon: RowIcon?
    var grayType = false

    var body: some View {
        if let icon {
            Label {
                name
            } icon: {
                switch icon {
                case .symbol(let symbol):
                    Image(systemName: symbol).interfaceFont(.body).foregroundStyle(.secondary)
                case .type(let id) where grayType:
                    Image(typeGlyph: id).resizable().scaledToFit().foregroundStyle(.secondary)
                        .frame(width: ChipLooks.defaults.chipMarkSize, height: ChipLooks.defaults.chipMarkSize)
                case .type(let id): TonedGlyph(id: id)
                }
            }
        } else {
            name
        }
    }

    private var name: some View {
        // The system bolds a selected row by the table's state, which stops following the selection once the soft
        // selection has the table and the window's workspace is mounted again, so a place stayed bold after leaving it.
        // The mark says which row is selected.
        Text(title).interfaceFont(.body).fontWeight(.regular).lineLimit(1).truncationMode(.tail)
    }
}

/// A row of the Types section: the type's mark and name, a count at the trailing edge in line with the system's own,
/// and, where the row folds kinds under it, a chevron. Under the pointer a plus takes the count's place, which makes an
/// item of the type; the chevron and everything else stay where they are.
///
/// A kind sits one step in under its type: with its mark, the mark lies under its type's name; without, which the
/// person can choose in Settings, its name starts level with its type's.
struct SidebarTypeRow: View {
    let row: SidebarPlan.TypeRow
    let count: Int
    /// The largest count on a row that folds. The count column of every folding row is as wide as it, so their
    /// chevrons share one place whatever each count is.
    let widestFoldingCount: Int
    /// The indent columns before the row's own content, outermost first.
    let steps: [Step]
    let showsIcon: Bool
    /// Makes an item of the type, where the person can; nil leaves the count under the pointer.
    var add: (() -> Void)?
    /// What the plus makes, as its help says: "New Note".
    var addName = ""
    let toggle: () -> Void
    @State private var isHovering = false

    /// The padding above and below the content. The list's own row inset is set to zero (`listRowInsets`) so the
    /// guide runs unbroken from one row to the next, and this puts the space back inside the row.
    private static let verticalInset: CGFloat = 4

    /// Measured so that a count here ends where the system's count on the rows above does.
    private static let countInset: CGFloat = 4

    var body: some View {
        HStack(spacing: 0) {
            ForEach(steps.indices, id: \.self) { SidebarIndent(step: steps[$0]) }
            content.padding(.vertical, Self.verticalInset).padding(.trailing, Self.countInset)
        }
        .frame(maxHeight: .infinity)
        .onHover { isHovering = $0 }
        .accessibilityActions {
            if let add { Button(addName, action: add) }
        }
        .overlay(alignment: .trailing) {
            if row.isExpandable {
                HStack(spacing: 0) {
                    disclosure
                    SidebarCount(count: count, widest: widestFoldingCount).hidden().accessibilityHidden(true)
                }
                .padding(.trailing, Self.countInset)
            }
        }
    }

    private var disclosure: SidebarDisclosure {
        SidebarDisclosure(title: row.node.label, id: row.node.id, isExpanded: row.isExpanded, isButton: row.node.opens, toggle: toggle)
    }

    private var label: SidebarLabel {
        SidebarLabel(title: row.node.label, icon: showsIcon ? .type(row.node.icon) : nil)
    }

    /// The name and count read as one element; a chevron beside them stays a button of its own.
    private var content: some View {
        HStack(spacing: 0) {
            label
            Spacer(minLength: 8)
            if row.isExpandable { disclosure.hidden().accessibilityHidden(true) }
            ZStack(alignment: .trailing) {
                SidebarCount(count: count, widest: row.isExpandable ? widestFoldingCount : 0)
                    .opacity(isHovering && add != nil ? 0 : 1)
                if isHovering, let add {
                    SidebarPlus(name: addName, add: add).padding(.trailing, -4)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One column of a kind's indent before its content.
    struct Step: Equatable {
        /// Whether the column is as wide as the mark and the space after it that its parent's row has, plus `extra`.
        var spansParentMark: Bool
        var extra: CGFloat
    }

    static let subtypeIconsKey = "sidebarSubtypeIcons"

    /// How far a name sits in from its parent's name when the parent has no mark to step by.
    static let indent: CGFloat = 12

    /// Whether a row has a mark. Kinds lose theirs unless `subtypeIcons`; top-level types and groups keep theirs.
    static func showsIcon(_ row: SidebarPlan.TypeRow, subtypeIcons: Bool) -> Bool {
        subtypeIcons || row.depth == 0 || !row.node.opens
    }

    /// The columns before each row's content. A row under a parent with a mark starts where the parent's name does,
    /// with its mark or, with none, its name; a row under a parent with no mark steps in from the parent's name by
    /// `indent`.
    static func steps(for rows: [SidebarPlan.TypeRow], subtypeIcons: Bool) -> [[Step]] {
        var marks: [Bool] = []
        return rows.map { row in
            marks = Array(marks.prefix(row.depth)) + [showsIcon(row, subtypeIcons: subtypeIcons)]
            return (0..<row.depth).map { level in
                Step(spansParentMark: marks[level], extra: marks[level] ? 0 : indent)
            }
        }
    }
}

/// A row's count, in the size of the system's own on the rows above, which does not follow the base text size. A
/// column no narrower than `widest` keeps what stands beside it in one place.
private struct SidebarCount: View {
    let count: Int
    let widest: Int

    var body: some View {
        ZStack(alignment: .trailing) {
            if widest > 0 { Text(widest, format: .number).hidden().accessibilityHidden(true) }
            if count > 0 { Text(count, format: .number) }
        }
        .monospacedDigit()
        .font(.subheadline)
        .foregroundStyle(.tertiary)
    }
}

/// One column of a kind's indent: as wide as its parent's mark and the space after it, where the parent has one, and
/// `extra`.
private struct SidebarIndent: View {
    let step: SidebarTypeRow.Step

    var body: some View {
        HStack(spacing: 0) {
            if step.spansParentMark {
                // The system's own label gives the width of a mark and the space after it, so nesting follows its metrics.
                Label {
                    Text(verbatim: "")
                } icon: {
                    TonedGlyph(id: nil)
                }
                .interfaceFont(.body)
                .labelStyle(.titleAndIcon)
                .fixedSize()
                .hidden()
            }
            Color.clear.frame(width: step.extra)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
/// Rows as the sidebar draws them, with a system row above to show where its count sits.
private struct TypeRowsPreview: View {
    let nodes: [TypeNode]
    var collapsed: Set<String> = []
    var subtypeIcons = false

    var body: some View {
        let rows = Self.rows(nodes, depth: 0, collapsed: collapsed)
        let steps = SidebarTypeRow.steps(for: rows, subtypeIcons: subtypeIcons)
        let widest = rows.filter(\.isExpandable).map(\.node.count).max() ?? 0
        List {
            Section {
                SidebarLabel(title: "Library", icon: .symbol("square.grid.2x2"))
                    .badge(Text(412, format: .number).monospacedDigit())
            }
            Section("Types") {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    SidebarTypeRow(
                        row: row, count: row.node.count, widestFoldingCount: widest, steps: steps[index],
                        showsIcon: SidebarTypeRow.showsIcon(row, subtypeIcons: subtypeIcons)
                    ) {}
                    .listRowInsets(.vertical, 0)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private static func rows(_ nodes: [TypeNode], depth: Int, collapsed: Set<String>) -> [SidebarPlan.TypeRow] {
        nodes.flatMap { node in
            let isExpanded = !collapsed.contains(node.id)
            return [SidebarPlan.TypeRow(node: node, depth: depth, isExpanded: isExpanded)]
                + (isExpanded ? rows(node.children, depth: depth + 1, collapsed: collapsed) : [])
        }
    }

    private static func node(_ id: String, _ label: String, _ icon: String, count: Int, _ children: [TypeNode] = []) -> TypeNode {
        TypeNode(
            id: id, type: TypeID(id), label: label, icon: icon, count: count,
            total: count + children.map(\.total).reduce(0, +), children: children)
    }

    static let tree = [
        node("core.note", "Note", "lucide:file-text", count: 412),
        node(
            "aic.ticket", "Ticket", "lucide:ticket", count: 36,
            [
                node("aic.ticket.bug", "Bug", "lucide:bug", count: 9),
                node(
                    "aic.ticket.task", "Task", "lucide:list-checks", count: 21,
                    [
                        node("aic.ticket.task.chore", "Chore with a name long enough to run out of room", "lucide:wrench", count: 3),
                        node("aic.ticket.task.review", "Review", "lucide:eye", count: 0),
                    ]),
                node("aic.ticket.spike", "Spike", "lucide:zap", count: 2),
            ]),
        node("aic.project", "Project", "lucide:folder", count: 5),
    ]
}

#Preview("Types: folded open") {
    TypeRowsPreview(nodes: TypeRowsPreview.tree).frame(width: 260, height: 420)
}

#Preview("Types: folded shut") {
    TypeRowsPreview(nodes: TypeRowsPreview.tree, collapsed: ["aic.ticket"]).frame(width: 260, height: 420)
}

#Preview("Types: three levels, inner folded shut") {
    TypeRowsPreview(nodes: TypeRowsPreview.tree, collapsed: ["aic.ticket.task"]).frame(width: 260, height: 420)
}

#Preview("Types: icons on subtypes") {
    TypeRowsPreview(nodes: TypeRowsPreview.tree, subtypeIcons: true).frame(width: 260, height: 420)
}
#endif
