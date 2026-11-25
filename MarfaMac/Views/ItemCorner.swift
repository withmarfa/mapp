import SwiftUI

/// The corner of an item's page: Open where the page has somewhere outside the app to go, Aa where the page can be written,
/// Reader or Original where a web page has a Reader view, the text size of every page of text, and Focus last on every
/// page (`PageCorner.buttons`), less the controls the
/// person turned off in Settings > Editor, which the page's More menu offers instead. It is drawn by
/// `WindowCorner`, so Aa's formats open as a bar along the foot of the page. Each control is also a menu command and a
/// palette entry (`ItemCommand`), and runs the same code.
///
/// Focus and the open bar belong to the item they were chosen on (`DetailsPresentation`), so another item's page
/// never inherits either, and a format is never sent to an item the bar was not opened for.
struct ItemCorner: View {
    @CurrentLibrary private var library
    let item: Item
    /// Nil where the window has no editor, as for a file in a window of its own.
    let editor: EditorController?
    let details: DetailsPresentation
    @AppStorage(PageKey.cornerShowsFormats) private var showsFormats = true
    @AppStorage(PageKey.cornerShowsTextSize) private var showsTextSize = true
    @AppStorage(PageKey.cornerShowsFocus) private var showsFocus = true

    var body: some View {
        let layout = library.pageLayout(of: item)
        let kind = PageCornerKind(for: item, in: library, details: details, hasEditor: editor != nil)
        let fileView = details.fileViewing(of: item.id)
        let choice = PageCornerChoice(formats: showsFormats, textSize: showsTextSize, focus: showsFocus)
        let buttons = PageCorner.buttons(kind, shows: choice)
        let target = PageOpenTarget.of(item, in: library, file: details.fileURL(of: item.id))
        // The bar belongs to the page, not to Aa: View > Show Formats opens it with Aa left out of the corner.
        let formatsEditor = PageCorner.buttons(kind).contains(.formats) ? editor : nil
        let isBarOpen = formatsEditor != nil && details.isFormatsOpen(on: item.id)
        let isFocused = details.isFocused(on: item.id)
        WindowCorner(isCardOpen: isBarOpen, cardPlacement: .centeredAtFoot) {
            ForEach(buttons, id: \.self) { button in
                switch button {
                case .open:
                    if let target { PageOpenButton(target: target, item: item) }
                case .formats:
                    Button {
                        details.toggleFormats(on: item.id)
                    } label: {
                        if isBarOpen { Image(systemName: "xmark") } else { Text("Aa") }
                    }
                    .buttonStyle(CornerButtonStyle(isOn: isBarOpen))
                    .help(isBarOpen ? "Close Formats" : "Show Formats")
                    .accessibilityLabel(isBarOpen ? "Close Formats" : "Show Formats")
                    .accessibilityIdentifier("PageFormats")
                case .textSize:
                    TextSizeControl(isAvailable: PageCorner.sizesText(layout: layout, look: details.pageLook?.mode))
                case .look:
                    CornerSegmented(
                        label: "Reader or Original", selection: Binding { details.pageLook?.mode ?? .standard } set: { details.pageLook?.choose($0) },
                        options: [SourceViewMode.reader, .original]
                    ) { $0 == .reader ? "Reader" : "Original" }
                    .help("Reader or Original")
                    .accessibilityIdentifier("SourceViewMode")
                case .pages:
                    if let fileView { FilePagesControl(viewing: fileView) }
                case .zoom:
                    // Another file's control starts afresh, with no size half typed.
                    if let fileView { FileZoomControl(viewing: fileView).id(ObjectIdentifier(fileView)) }
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
                FormatsBar(editor: formatsEditor, item: item.id)
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
    let isShown: Bool

    func body(content: Content) -> some View {
        content.overlay { if isShown { ItemCorner(item: item, editor: editor, details: details) } }
    }
}

extension View {
    /// Escape closes the formats bar, then leaves Focus, while the keyboard is in this view. It passes the key on when
    /// neither is showing. Put it on the workspace or the page, never on a view that holds the command palette, quick
    /// add or a sheet, which keep Escape for themselves. The editor's page takes Escape itself
    /// (`EditorController.onEscape`).
    func escapesFromPage(_ details: DetailsPresentation) -> some View {
        onKeyPress(.escape) { details.escapeFromPage() ? .handled : .ignored }
    }

    /// Puts the corner of an item's page over it, ending where the right sidebar begins, unless `isShown` is false, as
    /// in a modal, whose page has no corner.
    func itemCorner(_ item: Item, editor: EditorController?, details: DetailsPresentation, isShown: Bool = true) -> some View {
        modifier(ItemCornerModifier(item: item, editor: editor, details: details, isShown: isShown))
    }
}

extension PageCornerKind {
    /// The corner's kind for `item`'s page, from what the page and the window have ready.
    @MainActor
    init(for item: Item, in library: any ItemLibrary, details: DetailsPresentation, hasEditor: Bool) {
        let fileView = details.fileViewing(of: item.id)
        self.init(
            layout: library.pageLayout(of: item), hasReader: details.pageLook?.item == item.id,
            canWrite: item.allows(.text) && hasEditor, keepsText: library.catalogue.itemTypes[item.type]?.bodyKey != nil,
            file: fileView?.kind, pageCount: fileView?.pages?.count,
            opens: PageOpenTarget.of(item, in: library, file: details.fileURL(of: item.id)) != nil)
    }
}
