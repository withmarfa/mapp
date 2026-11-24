import SwiftUI

/// Chooses the item the Link to Item command links to: the items by title, the most recently edited first,
/// narrowed by what is typed. Return or a click chooses; Cancel or Escape leaves the line as it was typed.
struct ItemLinkPicker: View {
    @CurrentLibrary private var library
    let editor: EditorController
    let itemID: ItemID
    @State private var query = ""
    @State private var highlighted = 0
    /// Read once, so typing in the field narrows a list that is already sorted.
    @State private var candidates: [Item] = []
    /// The items' titles folded once, so a keystroke folds only what was typed.
    @State private var titles = PaletteMatch.Titles()
    /// An item was chosen that no link can name alone, so the person is asked for another.
    @State private var refused = false

    private static let limit = 50

    private var matches: [Item] {
        let ranked = titles.ranked(candidates.map(\.title), query)
        return ranked.prefix(Self.limit).map { candidates[$0] }
    }

    var body: some View {
        let matches = matches
        VStack(alignment: .leading, spacing: 12) {
            Text("Link to Item").interfaceFont(.title2.bold())
            InlineSearchField(
                text: $query, prompt: String(localized: "Search Items"), identifier: "ItemLinkField",
                onDown: { moveHighlight(by: 1, count: matches.count) },
                onUp: { moveHighlight(by: -1, count: matches.count) },
                onSubmit: { choose(matches, at: highlighted) },
                onCancel: editor.cancelLinkRequest
            )
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matches.indices, id: \.self) { index in
                            row(matches[index], isHighlighted: index == highlighted)
                                .id(index)
                                .onTapGesture { choose(matches, at: index) }
                        }
                    }
                }
                .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
            }
            .overlay {
                if matches.isEmpty { ContentUnavailableView.search(text: query) }
            }
            if refused {
                Text("The item's title and path cannot be represented as an unambiguous file link.")
                    .interfaceFont(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { editor.cancelLinkRequest() }
                    .keyboardShortcut(.cancelAction)
                    .appButton(.secondary)
            }
        }
        .padding(20)
        .frame(width: 440, height: 460)
        .onKeyPress(.downArrow) {
            moveHighlight(by: 1, count: matches.count)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveHighlight(by: -1, count: matches.count)
            return .handled
        }
        .onChange(of: query) { highlighted = 0; refused = false }
        .task {
            candidates = library.itemsToLink(excluding: itemID)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ItemLinkPicker")
    }

    private func row(_ item: Item, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            TypeMark(icon: library.catalogue.icon(for: item.type), size: .row)
            Text(item.displayTitle).lineLimit(1)
            Spacer(minLength: 8)
            Text(library.placeLabel(of: item))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 6, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityIdentifier("ItemLinkRow.\(item.id.rawValue)")
    }

    private func moveHighlight(by step: Int, count: Int) {
        highlighted = min(max(highlighted + step, 0), max(count - 1, 0))
    }

    private func choose(_ matches: [Item], at index: Int) {
        guard matches.indices.contains(index) else { return }
        // The item is read again by identity as it is chosen, so a rename or a new twin since the list was made is seen.
        let id = matches[index].id
        Task { refused = !(await editor.finishLinkRequest(choosing: id)) }
    }
}
