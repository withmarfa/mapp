import SwiftUI

/// An item opened as a modal: a large, solid page over the window, which dims what is behind it. It hosts the same
/// item page the window shows, with the window's one editor, so no second editor writes the item while it is open
/// (the page beside the list steps aside, `MainView`). The right sidebar opens inside it. Escape, the close button and a
/// click on the dim area put it away, and `MainView` saves what was typed as it goes.
struct ItemModal: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser
    let editor: EditorController
    let details: DetailsPresentation
    @FocusState private var hasKeyboard: Bool

    private static let toolbarHeight: CGFloat = 52
    private static let sidebarWidth: CGFloat = 300
    private static let corner: CGFloat = 22
    /// The page's width, which the right sidebar adds to rather than takes from, as far as the window leaves room.
    private static let pageWidth: CGFloat = 1000
    private static let sideMargin: CGFloat = 110
    private static let verticalMargin: CGFloat = 60

    private func cardWidth(in window: CGFloat) -> CGFloat {
        let wanted = Self.pageWidth + (details.isPresented ? Self.sidebarWidth : 0)
        // Where the window is too narrow for the page, the card keeps a margin of its own.
        return max(0, min(wanted, window - 2 * Self.sideMargin))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Not a button: a click on the dim area is not a control to tab to, and Escape does the same.
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture { browser.closeModal() }
                    .accessibilityHidden(true)
                card
                    .frame(width: cardWidth(in: proxy.size.width))
                    .padding(.vertical, Self.verticalMargin)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Item"))
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("ItemModal")
        // The card takes the keyboard, so the arrow keys and Return reach it and not the layout behind it.
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboard)
        .onAppear { hasKeyboard = true }
        .onExitCommand { escape() }
        // An item that is gone from the library has nothing left to show.
        .onChange(of: browser.modalItem.map { library.item($0) == nil } ?? true) { _, isGone in
            if isGone { browser.closeModal() }
        }
    }

    private var card: some View {
        HStack(spacing: 0) {
            ItemDetail(browser: browser, editor: editor, details: details, backsToolbar: false)
                .safeAreaPadding(.top, Self.toolbarHeight)
                .overlay(alignment: .topTrailing) { toolbar }
            if details.isPresented {
                Divider()
                ItemInspectorHost(browser: browser, details: details, editor: editor)
                    .frame(width: Self.sidebarWidth)
            }
        }
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

    /// Up and down, full page and new window, Share and More, the right sidebar and close, each set in a capsule of
    /// glass at the page's trailing edge.
    private var toolbar: some View {
        let id = browser.modalItem
        let neighbors = browser.modalNeighbors(in: library, order: order)
        let tools = ItemToolbarActions(
            library: library, browser: browser, items: browser.selectedItems(in: library), editor: editor, details: details)
        return GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
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
                capsule {
                    Button(ItemOpening.fullPage.commandTitle, systemImage: ItemOpening.fullPage.symbol) {
                        if let id { browser.open([id], as: .fullPage) }
                    }
                    .help(Text(ItemOpening.fullPage.commandTitle))
                    .accessibilityIdentifier("ModalFullPage")
                    Button(ItemOpening.newWindow.commandTitle, systemImage: ItemOpening.newWindow.symbol) { openInNewWindow() }
                        .help(Text(ItemOpening.newWindow.commandTitle))
                        .accessibilityIdentifier("ModalNewWindow")
                }
                capsule {
                    tools.shareLink
                    tools.moreMenu
                }
                // Done stands in for Details while Customize Layout has the right sidebar, as in the window.
                if details.isCustomizingLayout {
                    LayoutDoneButton(details: details, editor: editor)
                } else {
                    capsule(isOn: details.isPresented) {
                        Button("Details", systemImage: "sidebar.right") { details.isPresented.toggle() }
                            .symbolVariant(details.isPresented ? .fill : .none)
                            .help(details.isPresented ? "Hide Details" : "Show Details")
                            .accessibilityIdentifier("DetailsToggle")
                    }
                }
                capsule {
                    Button("Close", systemImage: "xmark") { browser.closeModal() }
                        .help("Close")
                        .accessibilityIdentifier("ModalClose")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: Self.toolbarHeight)
        }
    }

    /// A capsule of glass holding buttons, filled with the accent color while the one it holds is on.
    private func capsule<Content: View>(isOn: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2) { content() }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 6)
            .frame(height: 32)
            .glassEffect(isOn ? .regular.tint(.accentColor) : .regular, in: .capsule)
    }

    /// Closes the modal and opens the item in a window of its own, once what was typed is saved.
    private func openInNewWindow() {
        guard let id = browser.modalItem else { return }
        browser.closeModal()
        editor.flush { kept in
            if kept { browser.open([id], as: .newWindow) }
        }
    }
}
