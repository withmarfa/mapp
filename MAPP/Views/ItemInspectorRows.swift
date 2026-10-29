import AppKit
import SwiftUI

/// The measures of the inspector at the default text size, which scale with the interface text.
enum InspectorMetrics {
    /// The name column of a row. It never takes more than `maxNameShare` of the width, so a large text size leaves
    /// the value room.
    static let nameWidth: CGFloat = 96
    static let maxNameShare: CGFloat = 0.4
    static let gap: CGFloat = 8
    static let rowPadding: CGFloat = 3
    /// The space between two sections, in place of a rule.
    static let sectionGap: CGFloat = 20
    /// The space between a section's heading and what it holds.
    static let headingGap: CGFloat = 6
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
enum InspectorSection: CaseIterable {
    case details, properties, relationships, tags

    var key: String {
        switch self {
        case .details: InterfaceKey.inspectorDetailsOpen
        case .properties: InterfaceKey.inspectorPropertiesOpen
        case .relationships: InterfaceKey.inspectorRelationshipsOpen
        case .tags: InterfaceKey.inspectorTagsOpen
        }
    }

    var identifier: String {
        switch self {
        case .details: "ItemInspectorDetails"
        case .properties: "ItemInspectorProperties"
        case .relationships: "ItemInspectorRelationships"
        case .tags: "ItemInspectorTags"
        }
    }
}

/// A section: a heading with a chevron at its end that folds what the section holds, open until the person folds it.
/// The heading is one button, so VoiceOver and the keyboard reach the chevron by it. A section that can take
/// something new has a small plus on its heading, beside the chevron.
struct InspectorSectionView<Content: View, Add: View>: View {
    @AppStorage private var isOpen: Bool
    let section: InspectorSection
    let title: LocalizedStringKey
    /// The plus control, given whether the heading is hovered.
    let add: (Bool) -> Add
    @ViewBuilder let content: Content

    init(_ section: InspectorSection, title: LocalizedStringKey,
         @ViewBuilder add: @escaping (Bool) -> Add, @ViewBuilder content: () -> Content) {
        _isOpen = AppStorage(wrappedValue: true, section.key)
        self.section = section
        self.title = title
        self.add = add
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            InspectorFoldHeading(title: title, isOpen: $isOpen, identifier: section.identifier, add: add)
            if isOpen { content }
        }
    }
}

extension InspectorSectionView where Add == EmptyView {
    init(_ section: InspectorSection, title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(section, title: title, add: { _ in EmptyView() }, content: content)
    }
}

/// A section's heading: the system's title with the disclosure at its end, and the plus, in the trailing column,
/// where the section takes something new.
struct InspectorFoldHeading<Add: View>: View {
    @Environment(\.interfaceTextSize) private var textSize
    let title: LocalizedStringKey
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
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: InspectorMetrics.foldColumn * scale)
                    .accessibilityHidden(true)
            }
            .interfaceFont(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
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
        .padding(.vertical, InspectorMetrics.rowPadding * scale)
        .interfaceFont(.body)
    }
}

/// A value drawn as plain text. A value with no space in it (a link, an ID, a hash) takes one line and is cut in the
/// middle, where its ends say most; a date takes one line and is cut at its end; a value of words wraps to three
/// lines. The whole value is its help.
struct InspectorText: View {
    let text: String
    var style: AnyShapeStyle = AnyShapeStyle(.primary)
    /// A date, whose day and time stay together: it is cut at its end before it wraps.
    var keepsOneLine = false

    static func isToken(_ text: String) -> Bool { !text.contains(where: \.isWhitespace) }

    static func lineLimit(for text: String, keepsOneLine: Bool) -> Int {
        keepsOneLine || isToken(text) ? 1 : 3
    }

    var body: some View {
        let token = Self.isToken(text) && !keepsOneLine
        Text(verbatim: text)
            .foregroundStyle(style)
            .lineLimit(Self.lineLimit(for: text, keepsOneLine: keepsOneLine))
            .truncationMode(token ? .middle : .tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    func body(content: Content) -> some View {
        let scale = InterfaceStyle.scale(for: textSize)
        content
            .frame(width: InspectorMetrics.trailingColumn * scale)
            .padding(.trailing, InspectorMetrics.foldColumn * scale)
    }
}

extension View {
    /// Puts the view in the inspector's trailing column, where every add plus and row menu lines up.
    func inspectorTrailingColumn() -> some View { modifier(InspectorTrailingColumn()) }
}
