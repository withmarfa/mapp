import SwiftUI

/// The page of the item chosen in a layout that spans the window, in a column beside it, when the place's Open Items says Beside the
/// List (`ItemOpening.besideList`). It is the window's one editor on a fourth place, after the list's page column, the
/// full page and the modal, so it shows only while none of those has the editor (`Browser.showsBesidePage`). Its one
/// corner button is Open as Page. Choosing another row replaces the page once the selection has rested
/// (`BesideSettler`). The column shows the item the editor holds, so it changes only once the text on the page is
/// handed over and the page holds the new item.
struct BesideColumn: ViewModifier {
    @CurrentLibrary private var library
    @AppStorage(ListKey.openItemsIn) private var opening = ItemOpening.standard
    /// Only watched: a saved view's Open Items is kept in the app's settings, which `Browser.chosenOpening` reads.
    @AppStorage(ViewLayouts.key) private var layouts = ViewLayouts()
    let browser: Browser
    let editor: EditorController
    let details: DetailsPresentation
    @State private var settler = BesideSettler()
    /// This column's identity for `Browser.columnBeside`.
    @State private var host = UUID()

    /// The column's width in points.
    static let width: CGFloat = 372

    func body(content: Content) -> some View {
        let _ = layouts
        let isShown = browser.showsBesidePage(opening: browser.chosenOpening ?? opening)
        HStack(spacing: 0) {
            content
            if isShown {
                Divider()
                // One container, so the column's frame, its corner and its accessibility element each apply once, to the
                // column and not to each branch. The corner is pinned to the column's foot whatever the page's height.
                ZStack {
                    // Until the page holds the first item, the column draws no head over another item's text.
                    if let held = editor.heldItemID {
                        ItemDetail(browser: browser, editor: editor, details: details, backsToolbar: false, showsCorner: false, itemID: held)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: Self.width)
                .frame(maxHeight: .infinity)
                .overlay { BesideCorner(browser: browser) }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Item"))
                .accessibilityIdentifier("BesideColumn")
            }
        }
        .onChange(of: isShown, initial: true) { browser.columnBeside(host, isShown: isShown) }
        .onDisappear { browser.columnBeside(host, isShown: false) }
        .onChange(of: isShown ? browser.selection.first : nil, initial: true) { _, chosen in
            settler.choose(chosen, held: editor.heldItemID, handOver: { editor.flush(then: $0) }) { id in
                if let item = library.item(id) { editor.open(item) { _ in } }
            }
        }
    }
}

/// The column's corner: Open as Page, which takes the chosen item to the whole window.
private struct BesideCorner: View {
    let browser: Browser

    var body: some View {
        WindowCorner {
            Button(ItemOpening.fullPage.commandTitle, systemImage: ItemOpening.fullPage.symbol) {
                browser.open(browser.selection, as: .fullPage)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(CornerButtonStyle())
            .help("Open as Page")
            .accessibilityIdentifier("BesideOpenAsPage")
        }
    }
}

extension View {
    /// Puts the page of the chosen item in a column at this layout's trailing edge, where Open Items says Beside the List.
    func besidePage(_ browser: Browser, editor: EditorController, details: DetailsPresentation) -> some View {
        modifier(BesideColumn(browser: browser, editor: editor, details: details))
    }
}
