import AppKit
import SwiftUI

/// The measures the right sidebar's parts share at the default text size, which scale with the interface text: the
/// panel's plus, the properties and the view panel.
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
    /// A heading's inset from the box's edges.
    static let headingInset: CGFloat = 4
    /// A section's box: its side padding, which is also how far a divider stops short of both edges, the height of
    /// a row in it, and its corners. The vertical padding is what a row of several lines keeps above and below.
    static let boxInset: CGFloat = 12
    static let boxRowHeight: CGFloat = 32
    static let boxRowPadding: CGFloat = 6
    static let boxRadius: CGFloat = 10
    static let boxStroke: CGFloat = 0.5
    /// The column at the trailing end of the inspector that holds every add plus and every row menu, so they line up
    /// down the inspector.
    static let trailingColumn: CGFloat = 20
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

/// A name in the secondary color in a column of its own, with its value beside it. Names and values start on one
/// baseline, whatever the value holds, and a name that does not fit its column wraps to a second line.
struct InspectorRow<Value: View>: View {
    @Environment(\.interfaceTextSize) private var textSize
    let name: Text
    let help: String
    @ViewBuilder let value: Value
    private var nameAction: (() -> Void)?

    /// Makes a click on the name do `action`, as it does on the page, where a value that holds a link is changed from
    /// its name. Nil leaves the name as text.
    func onNameTap(_ action: (() -> Void)?) -> Self {
        var row = self
        row.nameAction = action
        return row
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
                .onTapGesture { nameAction?() }
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                    min(InspectorMetrics.nameWidth * scale, width * InspectorMetrics.maxNameShare)
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
