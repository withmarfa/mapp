import SwiftUI

/// Chooses the note the Link to Note command links to: the notes by title, the most recently edited first,
/// narrowed by what is typed. Return or a click chooses; Cancel or Escape leaves the line as it was typed.
struct NoteLinkPicker: View {
    @CurrentLibrary private var library
    let editor: EditorController
    let note: ItemID
    @State private var query = ""
    @State private var highlighted = 0
    /// Read once, so typing in the field narrows a list that is already sorted.
    @State private var notes: [Item] = []
    /// The notes' titles folded once, so a keystroke folds only what was typed.
    @State private var titles = PaletteMatch.Titles()
    /// A note was chosen that no link can name alone, so the person is asked for another.
    @State private var refused = false
    @FocusState private var isFieldFocused: Bool

    private static let limit = 50

    private var matches: [Item] {
        let ranked = titles.ranked(notes.map(\.title), query)
        return ranked.prefix(Self.limit).map { notes[$0] }
    }

    var body: some View {
        let matches = matches
        VStack(alignment: .leading, spacing: 12) {
            Text("Link to Note").interfaceFont(.title2.bold())
            TextField("Search Notes", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .onSubmit { choose(matches, at: highlighted) }
                .accessibilityIdentifier("NoteLinkField")
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
            }
        }
        .padding(20)
        .frame(width: 440, height: 460)
        .onKeyPress(.downArrow) {
            highlighted = min(highlighted + 1, max(matches.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlighted = max(highlighted - 1, 0)
            return .handled
        }
        .onChange(of: query) { highlighted = 0; refused = false }
        .task {
            notes = library.notesToLink(excluding: note)
            isFieldFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("NoteLinkPicker")
    }

    private func row(_ item: Item, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text")
                .frame(width: 20)
                .foregroundStyle(isHighlighted ? .white : .secondary)
            Text(item.title).lineLimit(1)
            Spacer(minLength: 8)
            Text(library.placeLabel(of: item))
                .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                .lineLimit(1)
        }
        .foregroundStyle(isHighlighted ? .white : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.accentColor : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityIdentifier("NoteLinkRow.\(item.id.rawValue)")
    }

    private func choose(_ matches: [Item], at index: Int) {
        guard matches.indices.contains(index) else { return }
        // The note is read again by identity as it is chosen, so a rename or a new twin since the list was made is seen.
        refused = !editor.finishLinkRequest(choosing: matches[index].id)
    }
}
