import SwiftUI

/// An item opened as a modal: a large, solid page over the window, which dims what is behind it. It hosts the same
/// item page the window shows, with the window's one editor, so no second editor writes the item while it is open
/// (the page beside the list steps aside, `MainView`). It has no corner and no panel. Escape, the close button and a click
/// on the dim area put it away, and `MainView` saves what was typed as it goes.
/// The window's own toolbar is dimmed and inactive while it is open (`MainView`).
struct ItemModal: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser
    let editor: EditorController
    let details: DetailsPresentation
    @FocusState private var hasKeyboard: Bool

    /// The band the toolbar's buttons are centered in, and how far the page starts below the card's top, which puts
    /// the title about 92 points down (the header adds its own space above the title) and keeps a long title clear of
    /// the buttons.
    private static let toolbarHeight: CGFloat = 60
    private static let pageTop: CGFloat = 64
    /// The height of a button's capsule: the window toolbar's, not smaller.
    private static let buttonHeight: CGFloat = 35
    private static let corner: CGFloat = 22
    /// The card's margins to the window, from the board: 210 at the sides and 56 above and below in a window 1440 points
    /// wide, which makes the card 1020 by 788 in 1440 by 900. The side margin shrinks with a window narrower than that, so
    /// the card keeps its share of it, and stays 210 in a wider one.
    private static let sideMargin: CGFloat = 210
    private static let sideMarginShare: CGFloat = 210 / 1440
    private static let verticalMargin: CGFloat = 56

    /// The card's size in a window of `window`'s size.
    static func cardSize(in window: CGSize) -> CGSize {
        CGSize(
            width: max(0, window.width - 2 * min(sideMargin, window.width * sideMarginShare)),
            height: max(0, window.height - 2 * verticalMargin))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = Self.cardSize(in: proxy.size)
            ZStack {
                // Not a button: a click on the dim area is not a control to tab to, and Escape does the same.
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture { browser.closeModal() }
                    .accessibilityHidden(true)
                card
                    .frame(width: size.width, height: size.height)
            }
        }
        // The margins are to the window's edges, under the title bar as the board draws them.
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Item"))
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("ItemModal")
        // The card takes the keyboard, so the arrow keys and Return reach it and not the layout behind it.
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboard)
        // The modal has no panel to arrange a layout in, so one under way ends as it opens.
        .onAppear { hasKeyboard = true; details.endLayout() }
        .onExitCommand { escape() }
        // An item that is gone from the library has nothing left to show.
        .onChange(of: browser.modalItem.map { library.item($0) == nil } ?? true) { _, isGone in
            if isGone { browser.closeModal() }
        }
    }

    private var card: some View {
        ItemDetail(browser: browser, editor: editor, details: details, backsToolbar: false, showsCorner: false)
            .safeAreaPadding(.top, Self.pageTop)
            .overlay(alignment: .top) { toolbar }
        .ignoresSafeArea()
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(.rect(cornerRadius: Self.corner))
        .overlay { RoundedRectangle(cornerRadius: Self.corner).strokeBorder(.separator) }
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
    }

    private func escape() {
        if details.isCustomizingLayout { details.endLayout() } else if !details.escapeFromPage() { browser.closeModal() }
    }

    // MARK: The toolbar

    /// Close, then up and down, at the page's leading edge; Keep first on an item in the Feed, then Favorite, Share and
    /// More, then Open as Page at its trailing edge. Each set is a capsule of glass.
    private var toolbar: some View {
        let id = browser.modalItem
        let neighbors = browser.modalNeighbors(in: library, order: order)
        let tools = ItemToolbarActions(
            library: library, browser: browser, items: browser.selectedHeaderItems(in: library), editor: editor, details: details)
        return GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                capsule {
                    Button("Close", systemImage: "xmark") { browser.closeModal() }
                        .help("Close")
                        .accessibilityIdentifier("ModalClose")
                }
                capsule {
                    Button("Previous Item", systemImage: "chevron.up") { browser.moveModal(.previous, in: library, order: order) }
                        .disabled(neighbors.previous == nil)
                        .help("Previous Item")
                        .accessibilityIdentifier("ModalPrevious")
                    Button("Next Item", systemImage: "chevron.down") { browser.moveModal(.next, in: library, order: order) }
                        .disabled(neighbors.next == nil)
                        .help("Next Item")
                        .accessibilityIdentifier("ModalNext")
                }
                Spacer(minLength: 0)
                if let id, PageKeepButton.applies(to: id, in: library) {
                    // Keep moves on to the item after it, which the list behind may no longer hold once it is kept, and
                    // only while the modal still shows the item kept.
                    let following = neighbors.next
                    tools.withUndo { undoManager in
                        PageKeepButton(id: id, undoManager: undoManager) {
                            if let following, browser.modalItem == id { browser.moveModal(to: following) }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .frame(height: Self.buttonHeight)
                        .glassEffect(.regular, in: .capsule)
                    }
                }
                capsule {
                    tools.withUndo { FavoriteButton(ids: tools.ids, undoManager: $0) }
                    tools.shareLink
                    tools.moreMenu
                }
                capsule {
                    Button(ItemOpening.fullPage.commandTitle, systemImage: ItemOpening.fullPage.symbol) {
                        if let id { browser.open([id], as: .fullPage) }
                    }
                    .help("Open as Page")
                    .accessibilityIdentifier("ModalFullPage")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: Self.toolbarHeight)
        }
    }

    /// A capsule of glass holding buttons. Each button is a
    /// square of the toolbar's button height, so one alone is a circle and a pair is a capsule with no gap between them,
    /// as the window toolbar draws them.
    private func capsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            content()
                .frame(width: Self.buttonHeight, height: Self.buttonHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .labelStyle(.iconOnly)
        .foregroundStyle(.primary)
        .glassEffect(.regular, in: .capsule)
    }
}
