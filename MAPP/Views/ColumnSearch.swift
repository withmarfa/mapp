import SwiftUI

/// Search in a toolbar, as Mail keeps its own beside the list's buttons: a magnifying glass until it is clicked,
/// then a glass search field. Clearing the field and leaving it, or Escape, puts the glass back. SwiftUI's own
/// `searchable` cannot do this on macOS: it always goes to the window's end, never in a column, and has no
/// minimized form there.
///
/// In a list column the field takes the column's toolbar in place of its title. Elsewhere it is an item of its
/// own, with the controls of `leading` beside it as their own items, and it grows leftwards from the glass.
struct ColumnSearch<Leading: View>: ToolbarContent {
    enum Layout {
        /// Across a list column, whose width a toolbar item cannot tell, so the caller passes it.
        case column(width: CGFloat)
        /// An item of its own, at the trailing side of a full-width toolbar.
        case item
    }

    @Binding var isExpanded: Bool
    @Binding var text: String
    let prompt: String
    let layout: Layout
    /// Asks, each time it changes, for an open field to take the keyboard again.
    var focusRequests = 0
    var onSubmit: () -> Void = {}
    /// Down Arrow in the field, which hands the keyboard to the list.
    var onDown: () -> Void = {}
    @ViewBuilder let leading: () -> Leading

    private var field: some View {
        ColumnSearchField(text: $text, prompt: prompt, focusRequests: focusRequests, onSubmit: onSubmit, onDown: onDown) {
            text = ""
            isExpanded = false
        }
    }

    private var button: some View {
        Button("Search", systemImage: "magnifyingglass") { isExpanded = true }
            .help("Search")
    }

    var body: some ToolbarContent {
        switch layout {
        case .column(let width):
            if isExpanded {
                ToolbarItem(placement: .principal) {
                    field.frame(width: max(160, width - 24))
                }
                .sharedBackgroundVisibility(.visible)
            } else {
                ToolbarItemGroup {
                    button
                    leading()
                }
            }
        case .item:
            ToolbarItem(id: "collectionOptions") { leading() }
            ToolbarSpacer(.fixed)
            if isExpanded {
                ToolbarItem(id: "collectionSearchField") { field.frame(width: 320) }
                    .sharedBackgroundVisibility(.visible)
            } else {
                ToolbarItem(id: "collectionSearch") { button }
            }
        }
    }
}

/// A rounded search field for a toolbar's glass: a magnifier, the prompt, and a clear button once there is text.
/// It takes the keyboard as it appears, and draws neither a focus ring nor an accent selection.
struct ColumnSearchField: View {
    @Binding var text: String
    let prompt: String
    let focusRequests: Int
    let onSubmit: () -> Void
    let onDown: () -> Void
    let onEnd: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .interfaceFont(.body)
                .focused($isFocused)
                .focusEffectDisabled()
                .tint(.secondary)
                .accessibilityIdentifier("ColumnSearch")
                .onSubmit(onSubmit)
                .onKeyPress(.downArrow) { onDown(); return .handled }
                .onKeyPress(.escape) { onEnd(); return .handled }
            if !text.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ClearColumnSearch")
            }
        }
        .padding(.horizontal, 8)
        .onAppear {
            // The toolbar places the field once this returns; asked any sooner, the window keeps the keyboard where it was.
            DispatchQueue.main.async { isFocused = true }
        }
        .onChange(of: focusRequests) { isFocused = true }
        // Left empty, the field goes back to being a button.
        .onChange(of: isFocused) { if !isFocused, text.isEmpty { onEnd() } }
    }
}
