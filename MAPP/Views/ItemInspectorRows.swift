import AppKit
import SwiftUI

/// The measures of the inspector at the default text size, which scale with the interface text.
enum InspectorMetrics {
    /// The name column of a row. It never takes more than `maxNameShare` of the width, so a large text size leaves
    /// the value room.
    static let nameWidth: CGFloat = 96
    static let maxNameShare: CGFloat = 0.4
    static let gap: CGFloat = 8
    /// The space between two sections.
    static let sectionGap: CGFloat = 20
    /// The space between a section's heading and its box.
    static let headingGap: CGFloat = 6
    /// The space between the groups of a section that has several, each a small heading above a box of its own.
    static let groupGap: CGFloat = 14
    /// A heading's inset from the box's edges.
    static let headingInset: CGFloat = 4
    /// A section's box: its side padding, which is also how far a divider stops short of both edges, the height of
    /// a row in it, and its corners. The vertical padding is what a row of several lines keeps above and below.
    static let boxInset: CGFloat = 12
    static let boxRowHeight: CGFloat = 32
    static let boxRowPadding: CGFloat = 6
    static let boxRadius: CGFloat = 10
    static let boxStroke: CGFloat = 0.5
    /// A cell of Details: the gap between cells, the padding inside one (the board draws the bottom a point deeper
    /// than the top), its corners, the gap between its name and its value, and how many lines its value may take.
    static let cellGap: CGFloat = 6
    static let cellInsetH: CGFloat = 9
    static let cellInsetTop: CGFloat = 7
    static let cellInsetBottom: CGFloat = 8
    static let cellRadius: CGFloat = 9
    static let cellValueGap: CGFloat = 3
    static let cellNameSize: CGFloat = 11
    static let cellValueLines = 2
    /// The room between a link row's mark and its title, and between its title and its date.
    static let markGap: CGFloat = 8
    static let chipRadius: CGFloat = 7
    /// A chip's horizontal padding, both sides together.
    static let chipPadding: CGFloat = 16
    /// How far a row's hover fill reaches past its content, so the content stays level with the headings.
    static let rowInset: CGFloat = 6
    static let rowRadius: CGFloat = 6
    /// The column at the trailing end of the inspector that holds every add plus and every row menu, so they line up
    /// down the inspector. The fold chevron sits beyond it, in `foldColumn`.
    static let trailingColumn: CGFloat = 20
    static let foldColumn: CGFloat = 14
    /// The space between a heading's plus and the fold chevron.
    static let foldGap: CGFloat = 4

    /// The width of the name column: the longest name shown, or `fallback` until one is measured, and never more
    /// than `maxNameShare` of the `available` width.
    static func nameColumn(longest: CGFloat?, fallback: CGFloat, available: CGFloat) -> CGFloat {
        min(longest ?? fallback, available * maxNameShare)
    }
}

extension EnvironmentValues {
    /// The widest name among the rows of the inspector, which every row's name column takes, so Details and
    /// Properties line up. Nil until the rows have measured their names.
    @Entry var inspectorNameWidth: CGFloat?
}

/// The natural width of a row's name, which the inspector gathers as the widest.
private struct InspectorNameWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    /// Gives the rows below one name column, as wide as their longest name.
    func sharesInspectorNameColumn() -> some View { modifier(SharedNameColumn()) }
}

private struct SharedNameColumn: ViewModifier {
    @State private var width: CGFloat?

    func body(content: Content) -> some View {
        content
            .environment(\.inspectorNameWidth, width)
            .onPreferenceChange(InspectorNameWidthKey.self) { width = $0 > 0 ? $0 : nil }
    }
}

/// The inspector's sections, each of which folds and keeps whether it is open for every item and launch.
enum InspectorSectionKind: CaseIterable {
    case details, properties, relationships, linksInPage, linkedFrom, tags

    var key: String {
        switch self {
        case .details: InterfaceKey.inspectorDetailsOpen
        case .properties: InterfaceKey.inspectorPropertiesOpen
        case .relationships: InterfaceKey.inspectorRelationshipsOpen
        case .linksInPage: InterfaceKey.inspectorLinksInPageOpen
        case .linkedFrom: InterfaceKey.inspectorLinkedFromOpen
        case .tags: InterfaceKey.inspectorTagsOpen
        }
    }

    var identifier: String {
        switch self {
        case .details: "ItemInspectorDetails"
        case .properties: "ItemInspectorProperties"
        case .relationships: "ItemInspectorRelationships"
        case .linksInPage: "ItemInspectorLinksInPage"
        case .linkedFrom: "ItemInspectorLinkedFrom"
        case .tags: "ItemInspectorTags"
        }
    }
}

/// A section of the inspector: a heading above a grouped box, with the section's name, then its count, and a chevron at
/// the end that folds the box. The heading is one button, so VoiceOver and the keyboard reach the chevron by it. A
/// section that can take something new has a small plus on its heading, beside the chevron.
///
/// The box takes each view of `content` as a row, with a divider between rows, so a row is a view of its own, never a
/// stack of several. A section with nothing in it shows `placeholder` as its one row. A section that is not `boxed`
/// draws its content as it is, for Details, whose cells are boxes of their own, and for Relationships, whose groups each
/// draw one. Its `placeholder` is still a box of its own.
struct InspectorSection<Content: View, Add: View>: View {
    let title: LocalizedStringKey
    var count: Int?
    @Binding var isOpen: Bool
    let identifier: String
    var placeholder: LocalizedStringKey?
    var boxed = true
    /// The plus control, given whether the heading is hovered.
    let add: (Bool) -> Add
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            InspectorFoldHeading(title: title, count: count, isOpen: $isOpen, identifier: identifier, add: add)
            if isOpen {
                if let placeholder {
                    InspectorBox { Text(placeholder).foregroundStyle(.secondary) }
                } else if boxed {
                    InspectorBox { content }
                } else {
                    content
                }
            }
        }
    }
}

/// An `InspectorSection` that keeps whether it is open for every item and launch.
struct InspectorSectionView<Content: View, Add: View>: View {
    @AppStorage private var isOpen: Bool
    let kind: InspectorSectionKind
    let title: LocalizedStringKey
    var count: Int?
    var placeholder: LocalizedStringKey?
    var boxed = true
    let add: (Bool) -> Add
    @ViewBuilder let content: Content

    init(_ kind: InspectorSectionKind, title: LocalizedStringKey, count: Int? = nil, placeholder: LocalizedStringKey? = nil,
         boxed: Bool = true, @ViewBuilder add: @escaping (Bool) -> Add, @ViewBuilder content: () -> Content) {
        _isOpen = AppStorage(wrappedValue: true, kind.key)
        self.kind = kind
        self.title = title
        self.count = count
        self.placeholder = placeholder
        self.boxed = boxed
        self.add = add
        self.content = content()
    }

    var body: some View {
        InspectorSection(title: title, count: count, isOpen: $isOpen, identifier: kind.identifier, placeholder: placeholder,
                         boxed: boxed, add: add) { content }
    }
}

extension InspectorSectionView where Add == EmptyView {
    init(_ kind: InspectorSectionKind, title: LocalizedStringKey, count: Int? = nil, placeholder: LocalizedStringKey? = nil,
         boxed: Bool = true, @ViewBuilder content: () -> Content) {
        self.init(kind, title: title, count: count, placeholder: placeholder, boxed: boxed, add: { _ in EmptyView() },
                  content: content)
    }
}

/// A section's heading: the system's title, the count, and the disclosure at the end, and the plus, in the trailing
/// column, where the section takes something new.
struct InspectorFoldHeading<Add: View>: View {
    @Environment(\.interfaceTextSize) private var textSize
    let title: LocalizedStringKey
    var count: Int?
    @Binding var isOpen: Bool
    let identifier: String
    let add: (Bool) -> Add
    @State private var hovering = false

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        Button {
            withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(title)
                    if let count, count > 0 {
                        Text(count, format: .number).monospacedDigit().fontWeight(.regular).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: InspectorMetrics.foldColumn * scale)
                    .accessibilityHidden(true)
            }
            .interfaceFont(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, InspectorMetrics.headingInset)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
        .accessibilityHint(isOpen ? Text("Collapses the section") : Text("Expands the section"))
        .accessibilityIdentifier(identifier)
        .overlay(alignment: .trailing) {
            add(hovering).inspectorTrailingColumn()
        }
        .onHover { hovering = $0 }
    }
}

/// The grouped box of a section: each view of its content is a row at least `boxRowHeight` high, inset by `boxInset`,
/// with a divider above every row but the first that stops `boxInset` short of both edges.
struct InspectorBox<Content: View>: View {
    @Environment(\.interfaceTextSize) private var textSize
    @ViewBuilder let content: Content

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    row
                        .padding(.horizontal, InspectorMetrics.boxInset)
                        .padding(.vertical, InspectorMetrics.boxRowPadding)
                        .frame(maxWidth: .infinity, minHeight: InspectorMetrics.boxRowHeight * scale, alignment: .leading)
                        .overlay(alignment: .top) {
                            if row.id != rows.first?.id {
                                Rectangle().fill(.separator).frame(height: InspectorMetrics.boxStroke)
                                    .padding(.horizontal, InspectorMetrics.boxInset)
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .inspectorSurface(radius: InspectorMetrics.boxRadius)
    }
}

extension View {
    /// The fill and hairline of a box or a cell: white at 3% over the sidebar in dark, the system's control background in
    /// light.
    func inspectorSurface(radius: CGFloat) -> some View { modifier(InspectorSurface(radius: radius)) }
}

private struct InspectorSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(scheme == .dark ? Color.white.opacity(0.03) : Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay { shape.strokeBorder(.separator, lineWidth: InspectorMetrics.boxStroke) }
            .clipShape(shape)
    }
}

/// A fact of Details in a small box of its own: its name above its value, as the design's `.m-insp-cell`. The value
/// takes up to `cellValueLines` lines, cut at its end, or one line cut in the middle where it has no space in it.
struct InspectorCell<Value: View>: View {
    @Environment(\.interfaceTextSize) private var textSize
    let name: String
    @ViewBuilder let value: Value

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        VStack(alignment: .leading, spacing: InspectorMetrics.cellValueGap * scale) {
            Text(verbatim: name)
                .interfaceFont(.system(size: InspectorMetrics.cellNameSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            value
                .interfaceFont(.body)
        }
        .padding(.horizontal, InspectorMetrics.cellInsetH)
        .padding(.top, InspectorMetrics.cellInsetTop)
        .padding(.bottom, InspectorMetrics.cellInsetBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .inspectorSurface(radius: InspectorMetrics.cellRadius)
        .accessibilityElement(children: .contain)
    }
}

/// Lays cells out two to a row. A cell whose value is too long for half the width takes a whole row; a cell left with
/// no partner sits alone in the first column, as wide as the others. Cells of a row are as tall as the tallest.
struct InspectorCellGrid: Layout {
    var spacing: CGFloat

    /// Whether a cell whose value one line needs `ideal` wide does not fit a column of `column`.
    static func takesWholeRow(ideal: CGFloat, column: CGFloat) -> Bool { ideal > column + 0.5 }

    /// The cells of each row, by index.
    private func rows(of subviews: Subviews, width: CGFloat) -> [[Int]] {
        let column = (width - spacing) / 2
        var rows: [[Int]] = []
        var open: [Int] = []
        for index in subviews.indices {
            if Self.takesWholeRow(ideal: subviews[index].sizeThatFits(.unspecified).width, column: column) {
                if !open.isEmpty { rows.append(open); open = [] }
                rows.append([index])
            } else {
                open.append(index)
                if open.count == 2 { rows.append(open); open = [] }
            }
        }
        if !open.isEmpty { rows.append(open) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let heights = rows(of: subviews, width: width).map { row in
            row.map { subviews[$0].sizeThatFits(.init(width: rowWidth(of: row, subviews: subviews, width: width), height: nil)).height }.max() ?? 0
        }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, width: bounds.width) {
            let cell = rowWidth(of: row, subviews: subviews, width: bounds.width)
            let height = row.map { subviews[$0].sizeThatFits(.init(width: cell, height: nil)).height }.max() ?? 0
            for (column, index) in row.enumerated() {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (cell + spacing), y: y), anchor: .topLeading,
                    proposal: .init(width: cell, height: height))
            }
            y += height + spacing
        }
    }

    /// A row's cell: half the width less the gap, or all of it for a cell that takes the row.
    private func rowWidth(of row: [Int], subviews: Subviews, width: CGFloat) -> CGFloat {
        let column = (width - spacing) / 2
        if row.count == 1, Self.takesWholeRow(ideal: subviews[row[0]].sizeThatFits(.unspecified).width, column: column) { return width }
        return column
    }
}

/// A name in the secondary color in a column of its own, with its value beside it. Names and values start on one
/// baseline, whatever the value holds, and a name that does not fit its column wraps to a second line.
struct InspectorRow<Value: View>: View {
    @Environment(\.interfaceTextSize) private var textSize
    @Environment(\.inspectorNameWidth) private var sharedNameWidth
    let name: Text
    let help: String
    @ViewBuilder let value: Value

    init(name: LocalizedStringResource, @ViewBuilder value: () -> Value) {
        self.name = Text(name)
        help = String(localized: name)
        self.value = value()
    }

    /// A name that comes from Marfa, shown as it is.
    init(verbatimName: String, @ViewBuilder value: () -> Value) {
        name = Text(verbatim: verbatimName)
        help = verbatimName
        self.value = value()
    }

    /// A field's label, which the app may have a translation for.
    init(fieldLabel: String, @ViewBuilder value: () -> Value) {
        name = Text(LocalizedStringKey(fieldLabel))
        help = fieldLabel
        self.value = value()
    }

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(alignment: .firstTextBaseline, spacing: InspectorMetrics.gap * scale) {
            name
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .help(help)
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                    InspectorMetrics.nameColumn(longest: sharedNameWidth, fallback: InspectorMetrics.nameWidth * scale, available: width)
                }
                .background {
                    // Measured on one line, so the column fits the whole name.
                    name.lineLimit(1).fixedSize().hidden().background {
                        GeometryReader { Color.clear.preference(key: InspectorNameWidthKey.self, value: ceil($0.size.width)) }
                    }
                }
            value
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .interfaceFont(.body)
    }
}

/// A value drawn as plain text. A value with no space in it (a link, an ID, a hash) takes one line and is cut in the
/// middle, where its ends say most; a date takes one line and is cut at its end; a value of words wraps to three
/// lines (`lines`). The whole value is its help. A value nothing edits may end at the trailing edge, as the design's
/// box rows draw it.
struct InspectorText: View {
    let text: String
    var style: AnyShapeStyle = AnyShapeStyle(.primary)
    /// A date, whose day and time stay together: it is cut at its end before it wraps.
    var keepsOneLine = false
    var lines = 3
    var endsAtTrailingEdge = false

    static func isToken(_ text: String) -> Bool { !text.contains(where: \.isWhitespace) }

    static func lineLimit(for text: String, keepsOneLine: Bool, lines: Int = 3) -> Int {
        keepsOneLine || isToken(text) ? 1 : lines
    }

    var body: some View {
        let token = Self.isToken(text) && !keepsOneLine
        Text(verbatim: text)
            .foregroundStyle(style)
            .lineLimit(Self.lineLimit(for: text, keepsOneLine: keepsOneLine, lines: lines))
            .truncationMode(token ? .middle : .tail)
            .multilineTextAlignment(endsAtTrailingEdge ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: endsAtTrailingEdge ? .trailing : .leading)
            .help(String(text.prefix(600)))
    }
}

/// The text an empty value shows. Text fields and menus share one colour, because a
/// hierarchical style dims twice inside a menu label and a text field's own prompt colour differs from it.
struct InspectorPlaceholder: View {
    static let color = Color(nsColor: .placeholderTextColor)

    let text: LocalizedStringKey

    var body: some View {
        Text(text).foregroundStyle(Self.color)
    }
}

/// Puts text on the pasteboard, for the Copy of a value's menu.
enum InspectorPasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// A row of a list in the inspector: it fills lightly under the pointer and when pressed, and reaches past its
/// content by `rowInset` so its content stays level with the rows above it.
struct InspectorRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, InspectorMetrics.rowInset)
                .padding(.vertical, 4)
                .background(
                    configuration.isPressed ? AnyShapeStyle(.quaternary) : hovering ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: InspectorMetrics.rowRadius, style: .continuous)
                )
                .contentShape(.rect(cornerRadius: InspectorMetrics.rowRadius, style: .continuous))
                .padding(.horizontal, -InspectorMetrics.rowInset)
                // The box sets a row's height, so the fill's room above and below does not add to it.
                .padding(.vertical, -4)
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// A quietly filled, rounded chip around the view, for a value that has a shape of its own, such as a tag.
    func inspectorChip() -> some View {
        padding(.horizontal, InspectorMetrics.chipPadding / 2)
            .padding(.vertical, 3)
            .background(.quinary, in: .rect(cornerRadius: InspectorMetrics.chipRadius, style: .continuous))
    }
}

/// The context menu a row of the inspector offers: whether the page shows it too.
struct ShowOnPageMenu: View {
    let isShown: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle("Show on Page", isOn: Binding(get: { isShown }, set: { onChange($0) }))
            .accessibilityIdentifier("ShowOnPage")
    }
}

extension View {
    /// Offers Show on Page on the view, where the inspector can change it.
    @ViewBuilder func showOnPageMenu(isShown: Bool, onChange: ((Bool) -> Void)?) -> some View {
        if let onChange {
            contextMenu { ShowOnPageMenu(isShown: isShown, onChange: onChange) }
        } else {
            self
        }
    }
}

/// The mark of a small plus: drawn in the clear color rather than faded to nothing while hidden, so its button stays
/// in the accessibility tree and VoiceOver reaches it always.
private struct InspectorPlusMark: View {
    @Environment(\.interfaceTextSize) private var textSize
    let isVisible: Bool
    /// A menu names itself from its label's content, so the label carries the name.
    let name: LocalizedStringKey

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        Image(systemName: "plus")
            .font(.system(size: 11 * scale, weight: .semibold))
            .foregroundStyle(isVisible ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.clear))
            .frame(width: InspectorMetrics.trailingColumn * scale, height: InspectorMetrics.trailingColumn * scale)
            .contentShape(.rect)
            .accessibilityLabel(name)
    }
}

/// The small plus that adds to a section or a relationship. It shows while the pointer is over the row it ends or the
/// plus has the keyboard.
struct InspectorPlusButton: View {
    let accessibilityLabel: LocalizedStringKey
    let identifier: String
    let isRowHovered: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) { InspectorPlusMark(isVisible: isRowHovered || isFocused, name: accessibilityLabel) }
            .buttonStyle(.plain)
            .focused($isFocused)
            .help(accessibilityLabel)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(identifier)
    }
}

/// The same plus where there is a choice of what to add, from a menu.
struct InspectorPlusMenu<Content: View>: View {
    let accessibilityLabel: LocalizedStringKey
    let identifier: String
    let isRowHovered: Bool
    @ViewBuilder let content: Content
    @FocusState private var isFocused: Bool

    var body: some View {
        Menu {
            content
        } label: {
            InspectorPlusMark(isVisible: isRowHovered || isFocused, name: accessibilityLabel)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // A menu button draws its label in the system's color whatever the label's style says, so it is hidden by
        // opacity. Fully transparent, a view leaves the accessibility tree; this faint, it stays in it and shows nothing.
        .opacity(isRowHovered || isFocused ? 1 : 0.002)
        .focused($isFocused)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }
}

private struct InspectorTrailingColumn: ViewModifier {
    @Environment(\.interfaceTextSize) private var textSize
    let clearsFold: Bool

    func body(content: Content) -> some View {
        let scale = InterfaceStyle.scale(for: textSize)
        content
            .frame(width: InspectorMetrics.trailingColumn * scale)
            .padding(.trailing, clearsFold ? (InspectorMetrics.foldColumn + InspectorMetrics.foldGap) * scale : 0)
    }
}

extension View {
    /// Puts the view in the inspector's trailing column, where every add plus and row menu lines up. A heading's plus
    /// clears the chevron's column; a row in a box ends at the box's inset instead.
    func inspectorTrailingColumn(clearsFold: Bool = true) -> some View { modifier(InspectorTrailingColumn(clearsFold: clearsFold)) }
}
