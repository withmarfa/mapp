import SwiftUI

/// A sidebar row's mark and name, laid out as the system lays out its own sidebar labels. Without a mark it is the
/// name alone.
struct SidebarLabel: View {
    let title: String
    let symbol: String?

    var body: some View {
        if let symbol {
            Label {
                name
            } icon: {
                Image(systemName: symbol).interfaceFont(.body).foregroundStyle(.secondary)
            }
        } else {
            name
        }
    }

    private var name: some View {
        Text(title).interfaceFont(.body).lineLimit(1).truncationMode(.tail)
    }
}

/// A row of the Types section: the type's mark and name, a count at the trailing edge in line with the system's own,
/// and, where the row folds subtypes under it, a chevron.
///
/// A subtype sits one step in under its parent, and a thin guide runs down the rows the parent holds and bends into
/// each of them. A subtype either keeps its mark, so the mark lies under its parent's name, or has none, so its name
/// starts a small step in from its parent's.
struct SidebarTypeRow: View {
    let row: SidebarPlan.TypeRow
    let count: Int
    /// The largest count on a row that folds. The count column of every folding row is as wide as it, so their
    /// chevrons share one place whatever each count is.
    let widestFoldingCount: Int
    /// The guide columns before the row's own content, outermost first.
    let steps: [Step]
    let showsIcon: Bool
    let chevron: SidebarExperiment.ChevronPlace
    /// Told when the row is clicked anywhere but on its chevron, with when the press began; nil where a click does
    /// nothing of its own.
    var reselect: ((Date) -> Void)?
    let toggle: () -> Void

    @State private var pressBegan: Date?

    /// The padding above and below the content. The list's own row inset is set to zero (`listRowInsets`) so the
    /// guide runs unbroken from one row to the next, and this puts the space back inside the row.
    private static let verticalInset: CGFloat = 4

    /// Measured so that a count here ends where the system's count on the rows above does.
    private static let countInset: CGFloat = 4

    var body: some View {
        HStack(spacing: 0) {
            ForEach(steps.indices, id: \.self) { SidebarGuide(step: steps[$0]) }
            content.padding(.vertical, Self.verticalInset).padding(.trailing, Self.countInset)
        }
        .frame(maxHeight: .infinity)
        .background {
            // Behind the content, so the chevron on top keeps its own clicks.
            if let reselect {
                Color.clear.contentShape(.rect).simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if pressBegan == nil { pressBegan = .now } }
                        .onEnded { value in
                            defer { pressBegan = nil }
                            guard let began = pressBegan, abs(value.translation.width) < 4, abs(value.translation.height) < 4 else { return }
                            reselect(began)
                        })
            }
        }
        .overlay(alignment: .trailing) {
            if chevron == .trailing, row.isExpandable {
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
        SidebarLabel(title: row.node.label, symbol: showsIcon ? row.node.symbol : nil)
    }

    @ViewBuilder private var content: some View {
        switch chevron {
        case .trailing:
            // The name and count read as one element; the chevron beside them stays a button of its own.
            HStack(spacing: 0) {
                label
                Spacer(minLength: 8)
                if row.isExpandable { disclosure.hidden().accessibilityHidden(true) }
                SidebarCount(count: count, widest: row.isExpandable ? widestFoldingCount : 0)
            }
            .accessibilityElement(children: .combine)
        case .afterName:
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    label
                    if row.isExpandable { disclosure.fixedSize() }
                }
                Spacer(minLength: 8)
                SidebarCount(count: count, widest: 0)
            }
        case .leading:
            // Every row holds the slot, so the marks of the rows at one depth stay in line.
            HStack(spacing: 0) {
                if row.isExpandable { disclosure } else { disclosure.hidden().accessibilityHidden(true) }
                HStack(spacing: 0) {
                    label
                    Spacer(minLength: 8)
                    SidebarCount(count: count, widest: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// One column of the guide before a row's content.
    struct Step: Equatable {
        /// Whether the guide carries on below the row, and whether it ends at this row's own bend.
        var continues: Bool
        var bends: Bool
        /// Whether the column is as wide as the mark and the space after it that its parent's row has, plus `extra`.
        var spansParentMark: Bool
        var extra: CGFloat
    }

    static let subtypeIconsKey = "sidebarSubtypeIcons"

    /// How far a name sits in from its parent's name when either row has no mark to step by.
    static let indent: CGFloat = 12
    /// The horizontal part of a bend, and the gap it stops short of what follows.
    static let elbow: CGFloat = 9
    static let elbowGap: CGFloat = 3

    /// Whether a row has a mark. Subtypes lose theirs unless `subtypeIcons`; top-level types and groups keep theirs.
    static func showsIcon(_ row: SidebarPlan.TypeRow, subtypeIcons: Bool) -> Bool {
        subtypeIcons || row.depth == 0 || !row.node.opens
    }

    /// The columns before each row's content. A row with a mark under a parent with a mark sits under the parent's
    /// name, as the rows always have; any other row steps in from its parent's name by `indent`.
    static func steps(for rows: [SidebarPlan.TypeRow], subtypeIcons: Bool) -> [[Step]] {
        let flags = guides(for: rows)
        var marks: [Bool] = []
        return rows.indices.map { index in
            let row = rows[index]
            marks = Array(marks.prefix(row.depth)) + [showsIcon(row, subtypeIcons: subtypeIcons)]
            return flags[index].indices.map { level in
                Step(
                    continues: flags[index][level], bends: level == row.depth - 1, spansParentMark: marks[level],
                    extra: marks[level] && marks[level + 1] ? 0 : indent)
            }
        }
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
            if widest > 0 { Text(widest, format: .number).hidden().accessibilityHidden(true) }
            if count > 0 { Text(count, format: .number) }
        }
        .monospacedDigit()
        .font(.subheadline)
        .foregroundStyle(.tertiary)
    }
}

/// One column of a subtype's indent. It ends at the left edge of what follows, a short bend before it: a guide runs
/// down it, and in the innermost column bends toward the row.
private struct SidebarGuide: View {
    let step: SidebarTypeRow.Step

    var body: some View {
        SidebarGuideLayout(spansParentMark: step.spansParentMark, extra: step.extra) {
            if step.spansParentMark {
                // The system's own label gives the width of a mark and the space after it, so nesting follows its metrics.
                Label {
                    Text(verbatim: "")
                } icon: {
                    Image(systemName: "circle")
                }
                .interfaceFont(.body)
                .hidden()
            }
            GuideShape(continues: step.continues, bends: step.bends).stroke(.quaternary, lineWidth: 1)
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

/// Sizes a column as its parent's mark, where it has one, and `extra`, and draws the guide in its last stretch.
private struct SidebarGuideLayout: Layout {
    let spansParentMark: Bool
    let extra: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let mark = spansParentMark ? subviews[0].sizeThatFits(.unspecified).width : 0
        return CGSize(width: mark + extra, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if spansParentMark { subviews[0].place(at: bounds.origin, proposal: .unspecified) }
        let length = SidebarTypeRow.elbow
        subviews[subviews.count - 1].place(
            at: CGPoint(x: bounds.maxX - SidebarTypeRow.elbowGap - length, y: bounds.minY),
            proposal: ProposedViewSize(width: length, height: bounds.height))
    }
}

/// A guide in its rectangle: down the left edge, and in a bend turning right at the middle to the far edge.
private nonisolated struct GuideShape: Shape {
    let continues: Bool
    let bends: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard continues || bends else { return path }
        let radius: CGFloat = 3
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
    var subtypeIcons = false
    var chevron = SidebarExperiment.ChevronPlace.trailing

    var body: some View {
        let rows = Self.rows(nodes, depth: 0, collapsed: collapsed)
        let steps = SidebarTypeRow.steps(for: rows, subtypeIcons: subtypeIcons)
        let widest = rows.filter(\.isExpandable).map(\.node.count).max() ?? 0
        List {
            Section {
                SidebarLabel(title: "All Items", symbol: "note.text")
                    .badge(Text(412, format: .number).monospacedDigit())
            }
            Section("Types") {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    SidebarTypeRow(
                        row: row, count: row.node.count, widestFoldingCount: widest, steps: steps[index],
                        showsIcon: SidebarTypeRow.showsIcon(row, subtypeIcons: subtypeIcons), chevron: chevron
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

#Preview("Types: icons on subtypes") {
    TypeRowsPreview(nodes: TypeRowsPreview.tree, subtypeIcons: true).frame(width: 260, height: 420)
}

#Preview("Types: chevron after the name") {
    TypeRowsPreview(nodes: TypeRowsPreview.tree, chevron: .afterName).frame(width: 260, height: 420)
}

#Preview("Types: chevron at the leading edge") {
    TypeRowsPreview(nodes: TypeRowsPreview.tree, chevron: .leading).frame(width: 260, height: 420)
}
#endif
