import SwiftUI

/// The formats Aa opens, as one bar of glass floating along the foot of the page: the text style as a pop-up showing the
/// current one, then bold, italic, strikethrough, highlight, code and link, then the bulleted, numbered and checklist
/// lists, then quote, code block and table. Every button is a command of the Format menu and runs it as the menu does
/// (`EditorController.apply`); one the caret cannot take is dimmed. The page's width and text size are in the corner
/// (`TextSizeControl`). In a column too narrow for the whole bar, the bar scrolls sideways.
struct FormatsBar: View {
    @Bindable var editor: EditorController
    let item: ItemID
    @Environment(\.interfaceTextSize) private var textSize

    static let styles: [Format] = [.body, .title, .heading, .subheading]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal) { row }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)
        }
        .windowGlass(in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formats")
        .accessibilityIdentifier("FormatsBar")
    }

    private var row: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        return HStack(spacing: 2) {
            stylePopUp
            divider
            ForEach([Format.bold, .italic, .strikethrough, .highlight, .code, .link], id: \.self) { button($0) }
            divider
            ForEach([Format.bulletList, .orderedList, .checklist], id: \.self) { button($0) }
            divider
            ForEach([Format.quote, .codeBlock, .table], id: \.self) { button($0) }
        }
        .padding(.horizontal, 6)
        .frame(height: (CornerMetrics.height + 4) * scale)
        .font(.system(size: 13 * scale))
    }

    private var divider: some View {
        Rectangle().fill(.primary.opacity(0.18)).frame(width: 0.5, height: 18).padding(.horizontal, 4)
    }

    /// The style the caret sits in; Body for any other, such as a deeper heading, which the pop-up does not offer.
    private var currentStyle: Format {
        Self.styles.first { $0 != .body && $0.isActive(in: editor.caret) } ?? .body
    }

    private var stylePopUp: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        return Menu {
            ForEach(Self.styles, id: \.self) { style in
                Toggle(isOn: Binding { style == currentStyle } set: { _ in apply(style) }) { Text(style.styleName) }
                    .disabled(!editor.canApply(style))
                    .accessibilityIdentifier("FormatStyle\(style.command.name)\(style.command.argument ?? "")")
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentStyle.styleName)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9 * scale, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 104 * scale, minHeight: 28 * scale)
            .contentShape(.rect(cornerRadius: 7))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!Self.styles.contains { editor.canApply($0) })
        .help("Text Style")
        .accessibilityLabel("Text Style")
        .accessibilityValue(Text(currentStyle.styleName))
        .accessibilityIdentifier("FormatStyleMenu")
    }

    private func button(_ format: Format) -> some View {
        let scale = InterfaceStyle.scale(for: textSize)
        let isOn = format.isActive(in: editor.caret)
        let isEnabled = editor.canApply(format)
        return Button { apply(format) } label: {
            Image(systemName: format.barSymbol)
                .frame(width: 30 * scale, height: 28 * scale)
                .background(.primary.opacity(isOn ? 0.14 : 0), in: .rect(cornerRadius: 7))
                .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .controlForeground(isEnabled: isEnabled)
        .disabled(!isEnabled)
        .help(Text(format.title))
        .accessibilityLabel(Text(format.title))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("Format\(format.command.name)")
    }

    private func apply(_ format: Format) {
        // The page may have moved to another item since the bar was drawn.
        guard editor.pageItemID == item else { return }
        editor.apply(format)
    }
}

extension Format {
    /// The name the style pop-up gives a text style, shorter than the Format menu's "Heading 1".
    var styleName: LocalizedStringKey {
        switch self {
        case .title: "Title"
        case .heading: "Heading"
        case .subheading: "Subheading"
        default: "Body"
        }
    }

    /// The symbol of a format's button in the bar.
    fileprivate var barSymbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .highlight: "highlighter"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        case .bulletList: "list.bullet"
        case .orderedList: "list.number"
        case .checklist: "checklist"
        case .quote: "text.quote"
        case .codeBlock: "terminal"
        case .table: "tablecells"
        default: "textformat"
        }
    }
}
