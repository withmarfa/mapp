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
    case details, properties, relationships, tags, linkedFrom

    var key: String {
        switch self {
        case .details: InterfaceKey.inspectorDetailsOpen
        case .properties: InterfaceKey.inspectorPropertiesOpen
        case .relationships: InterfaceKey.inspectorRelationshipsOpen
        case .tags: InterfaceKey.inspectorTagsOpen
        case .linkedFrom: InterfaceKey.inspectorLinkedFromOpen
        }
    }

    var identifier: String {
        switch self {
        case .details: "ItemInspectorDetails"
        case .properties: "ItemInspectorProperties"
        case .relationships: "ItemInspectorRelationships"
        case .tags: "ItemInspectorTags"
        case .linkedFrom: "ItemInspectorLinkedFrom"
        }
    }
}

/// A section: a heading with a chevron at its end that folds what the section holds, open until the person folds it.
/// The heading is one button, so VoiceOver and the keyboard reach the chevron by it.
struct InspectorSectionView<Content: View>: View {
    @AppStorage private var isOpen: Bool
    let section: InspectorSection
    let title: LocalizedStringKey
    var count: Int?
    @ViewBuilder let content: Content

    init(_ section: InspectorSection, title: LocalizedStringKey, count: Int? = nil, @ViewBuilder content: () -> Content) {
        _isOpen = AppStorage(wrappedValue: true, section.key)
        self.section = section
        self.title = title
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            InspectorFoldHeading(title: title, count: count, isOpen: $isOpen, identifier: section.identifier)
            if isOpen { content }
        }
    }
}

/// A section's heading: the system's headline with the disclosure at its end, and a count where the section lists
/// things.
struct InspectorFoldHeading: View {
    @Environment(\.interfaceTextSize) private var textSize
    let title: LocalizedStringKey
    var count: Int?
    @Binding var isOpen: Bool
    let identifier: String

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if let count {
                    Text(count, format: .number).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10 * InterfaceStyle.scale(for: textSize), weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .interfaceFont(.headline)
            .foregroundStyle(.primary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
        .accessibilityHint(isOpen ? Text("Collapses the section") : Text("Expands the section"))
        .accessibilityIdentifier(identifier)
    }
}

/// A name in the secondary color in a column of its own, with its value beside it. Names and values start on one
/// baseline, whatever the value holds, and a name that does not fit its column wraps to a second line.
struct InspectorRow<Value: View>: View {
    @Environment(\.interfaceTextSize) private var textSize
    @Environment(\.inspectorNameWidth) private var sharedNameWidth
    let name: Text
    let help: String
    /// A tighter row in a smaller size, for the facts under Details.
    var isCompact = false
    @ViewBuilder let value: Value

    init(name: LocalizedStringResource, isCompact: Bool = false, @ViewBuilder value: () -> Value) {
        self.name = Text(name)
        help = String(localized: name)
        self.isCompact = isCompact
        self.value = value()
    }

    /// A name that comes from Marfa, shown as it is.
    init(verbatimName: String, isCompact: Bool = false, @ViewBuilder value: () -> Value) {
        name = Text(verbatim: verbatimName)
        help = verbatimName
        self.isCompact = isCompact
        self.value = value()
    }

    /// A field's label, which the app may have a translation for.
    init(fieldLabel: String, isCompact: Bool = false, @ViewBuilder value: () -> Value) {
        name = Text(LocalizedStringKey(fieldLabel))
        help = fieldLabel
        self.isCompact = isCompact
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
        .padding(.vertical, (isCompact ? 1.5 : InspectorMetrics.rowPadding) * scale)
        .interfaceFont(isCompact ? .subheadline : .callout)
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

/// The label of a section's Add button or menu: a plus and the words, a fixed gap apart.
struct InspectorAddLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
            Text(title)
        }
        .interfaceFont(.callout)
    }
}

/// A section's Add button: a filled, rounded button with a plus.
struct InspectorAddButton: View {
    let title: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { InspectorAddLabel(title: title) }
            .buttonStyle(.bordered)
            .fixedSize()
            .accessibilityIdentifier(identifier)
    }
}

/// The same control where there is a choice of what to add, from a menu.
struct InspectorAddMenu<Content: View>: View {
    let title: LocalizedStringKey
    let identifier: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            InspectorAddLabel(title: title)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .fixedSize()
        .accessibilityIdentifier(identifier)
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

/// The small plus at the end of a relationship's name row, which adds to it. It shows while the pointer is over the
/// row or the plus has the keyboard. Hidden, it is drawn in the clear color rather than faded to nothing, so it
/// stays a button in the accessibility tree and VoiceOver reaches it always.
struct InspectorPlusButton: View {
    let accessibilityLabel: LocalizedStringKey
    let identifier: String
    let isRowHovered: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isRowHovered || isFocused ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.clear))
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }
}
