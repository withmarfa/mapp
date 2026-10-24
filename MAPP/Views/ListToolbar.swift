import SwiftUI

/// What acts on the list: Search and View Options together. View As
/// is on the page's toolbar, at the trailing side, where the gallery and the table have it too. In the gallery and
/// the table, which have no list column, their own toolbar holds all of it.
struct ListToolbar: ToolbarContent {
    @Bindable var browser: Browser
    /// The width the search field spans when it is out.
    let columnWidth: CGFloat

    var body: some ToolbarContent {
        ColumnSearch(
            isExpanded: $browser.isSearchExpanded,
            text: $browser.searchText,
            prompt: String(localized: "Search"),
            columnWidth: columnWidth,
            focusRequests: browser.searchFocusRequests,
            onDown: { browser.focusRequest = .list }
        ) {
            ViewOptionsMenu()
        }
    }
}

/// Starts an item in the place being shown.
struct NewItemButton: View {
    @CurrentLibrary private var library
    let browser: Browser?
    @State private var replacement: DraftReplacement?
    @State private var isConfirmingReplacement = false

    private struct DraftReplacement {
        let draft: NewItemDraft
        let typeID: String
    }

    var body: some View {
        Menu {
            if browser?.itemDraft?.hasText == true || browser?.isAwaitingCreation == true {
                Button("Continue Draft") { browser?.startItemDraft() }
                Divider()
            }
            ForEach(library.creatableTypes) { type in
                Button {
                    requestDraft(typeID: type.id.rawValue)
                } label: {
                    Label(type.label, systemImage: TypeSymbol.name(for: type.id, in: library.catalogue))
                }
                .disabled(browser?.isAwaitingCreation == true)
            }
        } label: {
            Label("New Item", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .help("New Item")
        .accessibilityIdentifier("NewItemToolbar")
        .disabled(browser == nil || !library.isLoaded || (browser?.itemDraft == nil && library.creatableTypes.isEmpty))
        .confirmationDialog("Discard the unfinished item?", isPresented: $isConfirmingReplacement,
                            titleVisibility: .visible, presenting: replacement) { replacement in
            Button("Continue Editing", role: .cancel) { browser?.startItemDraft() }
                .keyboardShortcut(.defaultAction)
            Button("Discard Draft", role: .destructive) {
                browser?.replaceItemDraft(replacement.draft, typeID: replacement.typeID)
            }
        } message: { _ in
            Text("The unfinished item contains unsaved text. Discard it to start a new item, or continue editing it.")
        }
    }

    private func requestDraft(typeID: String) {
        guard let browser, !browser.isAwaitingCreation else { return }
        if let draft = browser.itemDraft, draft.hasText {
            replacement = DraftReplacement(draft: draft, typeID: typeID)
            isConfirmingReplacement = true
        } else {
            browser.startItemDraft(typeID: typeID)
        }
    }
}
