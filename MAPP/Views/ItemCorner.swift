import SwiftUI

/// The corner of an item's page: Aa where the page is the editor, Reader or Original where a web page has a Reader view,
/// and Focus last on every page (`PageCorner.buttons`). It is drawn by `WindowCorner`, so Aa's card opens above the
/// buttons. Each control is also a menu command and a palette entry (`ItemCommand`), and runs the same code.
///
/// Focus and the open card belong to the item they were chosen on (`DetailsPresentation`), so another item's page
/// never inherits either, and a format is never sent to an item the card was not opened for.
struct ItemCorner: View {
    @CurrentLibrary private var library
    let item: Item
    /// Nil where the window has no editor, as for a file in a window of its own.
    let editor: EditorController?
    let details: DetailsPresentation
    /// The width of the content the corner sits over, which the card keeps inside.
    let width: CGFloat

    var body: some View {
        let layout = library.pageLayout(of: item)
        let buttons = PageCorner.buttons(layout: layout, hasReader: details.pageLook?.item == item.id)
        let formatsEditor = buttons.contains(.formats) ? editor : nil
        let isCardOpen = formatsEditor != nil && details.isFormatsOpen(on: item.id)
        let isFocused = details.isFocused(on: item.id)
        WindowCorner(
            isCardOpen: isCardOpen, cardWidth: PageCorner.cardWidth(forContentWidth: width, inset: WindowCorner<EmptyView, EmptyView>.inset)
        ) {
            ForEach(buttons, id: \.self) { button in
                switch button {
                case .formats:
                    Button { details.toggleFormats(on: item.id) } label: { Text("Aa") }
                        .buttonStyle(CornerButtonStyle(isOn: isCardOpen))
                        .help(isCardOpen ? "Hide Formats" : "Show Formats")
                        .accessibilityLabel("Formats")
                        .accessibilityIdentifier("PageFormats")
                case .look:
                    CornerSegmentedControl(
                        selection: Binding { details.pageLook?.mode ?? .standard } set: { details.pageLook?.choose($0) },
                        options: [(SourceViewMode.reader, LocalizedStringKey("Reader")), (SourceViewMode.original, LocalizedStringKey("Original"))]
                    )
                    .help("Reader or Original")
                    .accessibilityIdentifier("SourceViewMode")
                case .focus:
                    Button(isFocused ? "Leave Focus" : "Focus", systemImage: "arrow.up.left.and.arrow.down.right") {
                        details.toggleFocus(on: item.id)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(CornerButtonStyle(isOn: isFocused))
                    .disabled(details.isCustomizingLayout)
                    .help(isFocused ? "Leave Focus" : "Focus")
                    .accessibilityIdentifier("PageFocus")
                }
            }
        } card: {
            if let formatsEditor {
                FormatsCard(editor: formatsEditor, item: item.id)
            }
        }
        // The page takes Escape itself while it has the keyboard (`EditorController.onEscape`); anywhere else this does.
        .background {
            if isCardOpen || isFocused {
                Button("Leave Focus") { details.escapeFromPage() }
                    .keyboardShortcut(editor?.isFocused == true ? nil : .cancelAction)
                    .hidden()
            }
        }
        .onChange(of: item.id, initial: true) { details.pageShows(item.id) }
        .onDisappear { [id = item.id] in details.pageLeft(id) }
    }
}

private struct ItemCornerModifier: ViewModifier {
    let item: Item
    let editor: EditorController?
    let details: DetailsPresentation
    /// Wide until measured, so the card is never drawn narrow for a frame.
    @State private var width: CGFloat = .infinity

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay { ItemCorner(item: item, editor: editor, details: details, width: width) }
    }
}

extension View {
    /// Puts the corner of an item's page over it, ending where the right sidebar begins.
    func itemCorner(_ item: Item, editor: EditorController?, details: DetailsPresentation) -> some View {
        modifier(ItemCornerModifier(item: item, editor: editor, details: details))
    }
}

/// The formats Aa opens: the text style as a row, then bold to link, the lists, quote, code block and table, and last
/// the page's width and text size. Every button is a command of the Format menu or the View menu and runs it as they do:
/// `EditorController.apply` for a format, `PageWidthOptions` and `TextZoom` for the page.
struct FormatsCard: View {
    @Bindable var editor: EditorController
    let item: ItemID
    @AppStorage(PageKey.textSize) private var textSize = PageStyle().textSize

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(FormatsCard.styles, id: \.self) { style in
                    let isOn = style.isActive(in: editor.caret)
                    Button { apply(style) } label: {
                        Text(style.styleName)
                            .font(.system(size: style.styleSize, weight: style.styleWeight))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(.primary.opacity(isOn ? 0.1 : 0), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(editor.canApply(style) ? .primary : .tertiary)
                    .disabled(!editor.canApply(style))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityIdentifier("FormatStyle\(style.command.name)\(style.command.argument ?? "")")
                }
            }
            joined([(.bold, "bold"), (.italic, "italic"), (.strikethrough, "strikethrough"), (.highlight, "highlighter"),
                    (.code, "chevron.left.forwardslash.chevron.right"), (.link, "link")])
            HStack(spacing: 8) {
                joined([(.bulletList, "list.bullet"), (.orderedList, "list.number"), (.checklist, "checklist")])
                joined([(.quote, "text.quote"), (.codeBlock, "terminal"), (.table, "tablecells")])
            }
            Divider()
            HStack(spacing: 8) {
                PageWidthOptions()
                    .pickerStyle(.segmented)
                    .labelsHidden()
                textSizeButtons
            }
        }
        .padding(12)
        .interfaceFont(.callout)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formats")
        .accessibilityIdentifier("FormatsCard")
    }

    static let styles: [Format] = [.title, .heading, .subheading, .body]

    private func apply(_ format: Format) {
        // The page may have moved to another item since the card was drawn.
        guard editor.pageItemID == item else { return }
        editor.apply(format)
    }

    private func joined(_ formats: [(Format, String)]) -> some View {
        HStack(spacing: 0) {
            ForEach(formats.indices, id: \.self) { index in
                let (format, symbol) = formats[index]
                if index > 0 { Divider().padding(.vertical, 6) }
                let isOn = format.isActive(in: editor.caret)
                Button { apply(format) } label: {
                    Image(systemName: symbol)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(.primary.opacity(isOn ? 0.14 : 0), in: .rect(cornerRadius: 6))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(editor.canApply(format) ? .primary : .tertiary)
                .disabled(!editor.canApply(format))
                .help(Text(format.title))
                .accessibilityLabel(Text(format.title))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("Format\(format.command.name)")
            }
        }
        .padding(2)
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private var textSizeButtons: some View {
        let zoom = TextZoom.page
        return HStack(spacing: 0) {
            sizeButton("Make Text Smaller", "textformat.size.smaller", .smaller, zoom)
            Divider().padding(.vertical, 6)
            sizeButton("Actual Size", "textformat.size", .actual, zoom)
            Divider().padding(.vertical, 6)
            sizeButton("Make Text Bigger", "textformat.size.larger", .bigger, zoom)
        }
        .padding(2)
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 8))
        .fixedSize()
    }

    private func sizeButton(_ title: LocalizedStringKey, _ symbol: String, _ step: TextZoom.Step, _ zoom: TextZoom) -> some View {
        let isAvailable = zoom.size(after: step, from: textSize) != nil
        return Button { zoom.apply(step) } label: {
            Image(systemName: symbol).frame(width: 30, height: 28).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isAvailable ? .primary : .tertiary)
        .disabled(!isAvailable)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}

extension Format {
    /// The name the formats card gives a text style, shorter than the Format menu's "Heading 1".
    var styleName: LocalizedStringKey {
        switch self {
        case .title: "Title"
        case .heading: "Heading"
        case .subheading: "Subheading"
        default: "Body"
        }
    }

    fileprivate var styleSize: CGFloat {
        switch self {
        case .title: 17
        case .heading: 15
        default: 13
        }
    }

    fileprivate var styleWeight: Font.Weight {
        switch self {
        case .title: .bold
        case .heading, .subheading: .semibold
        default: .regular
        }
    }
}

/// Two choices in one glass capsule, the chosen one on a gray pill, such as Reader or Original. It is the corner's own
/// segmented control, drawn like its buttons.
struct CornerSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]
    @Environment(\.interfaceTextSize) private var textSize

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isOn = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.system(size: 13 * scale, weight: isOn ? .medium : .regular))
                        .padding(.horizontal, 12)
                        .frame(maxHeight: .infinity)
                        .background(.primary.opacity(isOn ? 0.14 : 0), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: CornerMetrics.height * scale)
        .glassEffect(.regular, in: .capsule)
    }
}
