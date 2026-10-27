import SwiftUI

/// A sidebar row's mark and name, laid out as the system lays out its own sidebar labels.
struct SidebarLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title).interfaceFont(.body).lineLimit(1).truncationMode(.tail)
        } icon: {
            Image(systemName: symbol).interfaceFont(.body).foregroundStyle(.secondary)
        }
    }
}

/// A row of the Types section: the type's mark and name, a count at the trailing edge in line with the system's own,
/// and, where the row folds subtypes under it, a chevron in one slot just before the count.
///
/// A subtype sits one step in, so its mark lies under its parent's name, and a thin guide runs from the parent's mark
/// down the rows it holds and bends into each of them.
struct SidebarTypeRow: View {
    let row: SidebarPlan.TypeRow
    let count: Int
    /// The largest count on a row that folds. The count column of every folding row is as wide as it, so their
    /// chevrons share one place whatever each count is.
    let widestFoldingCount: Int
    /// Whether a row after this one sits under the same parent at each level from the top, outermost first.
    let guides: [Bool]
    let toggle: () -> Void

    /// The padding above and below the content. The list's own row inset is set to zero (`listRowInsets`) so the
    /// guide runs unbroken from one row to the next, and this puts the space back inside the row.
    private static let verticalInset: CGFloat = 4

    /// Measured so that a count here ends where the system's count on the rows above does.
    private static let countInset: CGFloat = 4

    var body: some View {
        HStack(spacing: 0) {
            ForEach(guides.indices, id: \.self) { level in
                SidebarGuide(continues: guides[level], bends: level == guides.count - 1)
            }
            content.padding(.vertical, Self.verticalInset).padding(.trailing, Self.countInset)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            if row.isExpandable {
                HStack(spacing: 0) {
                    disclosure
                    SidebarCount(count: count, widest: widestFoldingCount).hidden()
                }
                .padding(.trailing, Self.countInset)
            }
        }
    }

    private var disclosure: SidebarDisclosure {
        SidebarDisclosure(title: row.node.label, id: row.node.id, isExpanded: row.isExpanded, isButton: row.node.opens, toggle: toggle)
    }

    /// The name and count read as one element; a chevron beside them stays a button of its own.
    private var content: some View {
        HStack(spacing: 0) {
            SidebarLabel(title: row.node.label, symbol: row.node.symbol)
            Spacer(minLength: 8)
            if row.isExpandable { disclosure.hidden() }
            SidebarCount(count: count, widest: row.isExpandable ? widestFoldingCount : 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// For each row, whether a row after it sits under the same parent at each level from the top, outermost first:
    /// where a guide carries on below the row, and where it ends at the row's own bend.
    static func guides(for rows: [SidebarPlan.TypeRow]) -> [[Bool]] {
        // A row at one depth closes every deeper level above it, so a later row there is under another parent.
        var carries: [Int: Bool] = [:]
        var result: [[Bool]] = []
        for row in rows.reversed() {
            result.append((0..<row.depth).map { carries[$0 + 1] ?? false })
            for level in carries.keys where level > row.depth { carries[level] = false }
            carries[row.depth] = true
        }
        return result.reversed()
    }
}

/// A row's count, in the size of the system's own on the rows above, which does not follow the base text size. A
/// column no narrower than `widest` keeps what stands beside it in one place.
private struct SidebarCount: View {
    let count: Int
    let widest: Int

    var body: some View {
        ZStack(alignment: .trailing) {
            if widest > 0 { Text(widest, format: .number).hidden() }
            if count > 0 { Text(count, format: .number) }
        }
        .monospacedDigit()
        .font(.subheadline)
        .foregroundStyle(.tertiary)
    }
}

/// One step of a subtype's indent: as wide as a mark and the space after it, so what follows lies under the parent's
/// name. A guide runs down it at the parent's mark, and in the innermost step bends toward the row.
private struct SidebarGuide: View {
    let continues: Bool
    let bends: Bool

    var body: some View {
        // The system's own label gives the step its width and the mark's centre, so nesting follows its metrics.
        SidebarGuideLayout {
            Label {
                Text(verbatim: "").alignmentGuide(.titleStart) { $0[.leading] }
            } icon: {
                Image(systemName: "circle").alignmentGuide(.iconCenter) { $0[HorizontalAlignment.center] }
            }
            .interfaceFont(.body)
            .hidden()
            GuideShape(continues: continues, bends: bends).stroke(.quaternary, lineWidth: 1)
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private nonisolated extension HorizontalAlignment {
    enum IconCenterID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.leading] }
    }

    enum TitleStartID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.leading] }
    }

    static let iconCenter = HorizontalAlignment(IconCenterID.self)
    static let titleStart = HorizontalAlignment(TitleStartID.self)
}

/// Sizes a step as its label, and draws the guide between the label's mark and its name.
private struct SidebarGuideLayout: Layout {
    /// Where a bend stops short of the name, so it does not touch the row's mark.
    static let gap: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let label = subviews[0].sizeThatFits(.unspecified)
        return CGSize(width: label.width, height: proposal.height ?? label.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let label = subviews[0].dimensions(in: .unspecified)
        subviews[0].place(at: bounds.origin, proposal: .unspecified)
        let start = label[.iconCenter]
        let end = label[.titleStart] - Self.gap
        subviews[1].place(
            at: CGPoint(x: bounds.minX + start, y: bounds.minY), proposal: ProposedViewSize(width: max(end - start, 0), height: bounds.height))
    }
}

/// A guide in its rectangle: down the left edge, and in a bend turning right at the middle to the far edge.
private nonisolated struct GuideShape: Shape {
    let continues: Bool
    let bends: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard continues || bends else { return path }
        let radius: CGFloat = 4
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: continues ? rect.maxY : rect.midY - radius))
        if bends {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY - radius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.midY), control: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}

#if DEBUG
/// Rows as the sidebar draws them, with a system row above to show where its count sits.
private struct TypeRowsPreview: View {
    let nodes: [TypeNode]
    var collapsed: Set<String> = []

    var body: some View {
        let rows = Self.rows(nodes, depth: 0, collapsed: collapsed)
        let guides = SidebarTypeRow.guides(for: rows)
        let widest = rows.filter(\.isExpandable).map(\.node.count).max() ?? 0
        List {
            Section {
                SidebarLabel(title: "All Items", symbol: "note.text")
                    .badge(Text(412, format: .number).monospacedDigit())
            }
            Section("Types") {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    SidebarTypeRow(row: row, count: row.node.count, widestFoldingCount: widest, guides: guides[index]) {}
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

    private static func node(_ id: String, _ label: String, _ symbol: String, count: Int, _ children: [TypeNode] = []) -> TypeNode {
        TypeNode(
            id: id, type: TypeID(id), label: label, symbol: symbol, count: count,
            total: count + children.map(\.total).reduce(0, +), children: children)
    }

    static let tree = [
        node("core.note", "Note", "doc.text", count: 412),
        node(
            "aic.ticket", "Ticket", "ticket", count: 36,
            [
                node("aic.ticket.bug", "Bug", "ladybug", count: 9),
                node(
                    "aic.ticket.task", "Task", "checklist", count: 21,
                    [
                        node("aic.ticket.task.chore", "Chore with a name long enough to run out of room", "wrench", count: 3),
                        node("aic.ticket.task.review", "Review", "eye", count: 0),
                    ]),
                node("aic.ticket.spike", "Spike", "bolt", count: 2),
            ]),
        node("aic.project", "Project", "folder", count: 5),
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
#endif
