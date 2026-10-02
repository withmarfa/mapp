import SwiftUI

/// The blank page starts in the window; its metadata becomes a file when writing begins.
struct NewItemPage: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    @Bindable var draft: NewItemDraft
    @StoredPageStyle private var style
    @State private var rejected = false
    @FocusState private var titleFocused: Bool
    @FocusState private var bodyFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            content
                .padding(.horizontal, style.horizontalInset(for: geometry.size.width))
                .padding(.top, CGFloat(style.textSize) * 2)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("Untitled", text: $draft.title)
                .font(.system(size: CGFloat(style.textSize) * 1.9, weight: .bold))
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .focused($titleFocused)
                .onSubmit { startWriting() }
                .accessibilityLabel("Title")
                .accessibilityIdentifier("NewItemTitle")
            HStack {
                Picker("Type", selection: $draft.typeID) {
                    ForEach(WorkbenchSchema.types) { type in Text(LocalizedStringKey(type.label)).tag(type.id) }
                }
                .accessibilityIdentifier("NewItemType")
                Picker("Parent", selection: $draft.parentID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(parents) { item in Text(item.title).tag(Optional(item.id)) }
                }
                .accessibilityIdentifier("NewItemParent")
            }
            if rejected {
                Text("Choose a unique title without characters that cannot be used in a file name, and a valid parent. Your draft is kept here.")
                    .font(.callout).foregroundStyle(.red)
                Button("Start Writing") { startWriting() }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft.body)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($bodyFocused)
                    .accessibilityLabel("Content")
                    .accessibilityIdentifier("NewItemBody")
                if draft.body.isEmpty {
                    Text("Start writing")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Button("Import File…", systemImage: "square.and.arrow.down") { browser.isImportingFiles = true }
                Spacer()
                Button("Back") { browser.isCreatingItem = false }
                    .help("Your draft is kept until you resume it with New Item.")
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .defaultFocus($titleFocused, true)
        .onChange(of: bodyFocused) { if bodyFocused { startWriting() } }
        .onChange(of: draft.body) { if !draft.body.isEmpty { startWriting() } }
        .onChange(of: draft.typeID) {
            if !parents.contains(where: { $0.id == draft.parentID }) { draft.parentID = nil }
            rejected = false
        }
        .onChange(of: draft.title) { rejected = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("NewItemPage")
    }

    private var parents: [AppItem] { library.creationParentCandidates(typeID: draft.typeID) }

    private func startWriting() {
        guard browser.isCreatingItem else { return }
        guard browser.createDraft(in: library, undoManager: undoManager) != nil else {
            rejected = true
            return
        }
    }
}
