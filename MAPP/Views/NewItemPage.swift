import SwiftUI

/// The blank page starts in the window; its metadata becomes a file when writing begins.
struct NewItemPage: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    @Bindable var draft: NewItemDraft
    @StoredPageStyle private var style
    @State private var rejected = false
    @FocusState private var titleFocused: Bool

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
                .foregroundStyle(Color(nsColor: .textColor))
                .focused($titleFocused)
                .onSubmit { startWriting() }
                .accessibilityLabel("Title")
                .accessibilityIdentifier("NewItemTitle")
            ItemChipLayout {
                Menu {
                    ForEach(WorkbenchSchema.types) { type in
                        Button { draft.typeID = type.id } label: {
                            if draft.typeID == type.id {
                                Label(LocalizedStringKey(type.label), systemImage: "checkmark")
                            } else {
                                Text(LocalizedStringKey(type.label))
                            }
                        }
                    }
                } label: {
                    ItemChipLabel(title: Text(LocalizedStringKey(WorkbenchSchema.definition(draft.typeID)?.label ?? "Type")))
                }
                .itemChipMenuStyle()
                .accessibilityLabel("Type")
                .accessibilityIdentifier("NewItemType")
                Menu {
                    Button("None") { draft.parentID = nil }
                    ForEach(parents) { item in
                        Button { draft.parentID = item.id } label: {
                            if draft.parentID == item.id { Label(item.title, systemImage: "checkmark") }
                            else { Text(item.title) }
                        }
                    }
                } label: {
                    ItemChipLabel(title: Text(parents.first { $0.id == draft.parentID }?.title ?? String(localized: "Add Parent")),
                                  systemImage: "square.stack")
                }
                .itemChipMenuStyle()
                .accessibilityLabel("Parent")
                .accessibilityIdentifier("NewItemParent")
            }
            if rejected {
                Text("Choose a unique title without characters that cannot be used in a file name, and a valid parent. Your draft is kept here.")
                    .interfaceFont(.callout).foregroundStyle(.red)
                Button("Start Writing") { startWriting() }
            }
            Button(action: startWriting) {
                Text("Start writing")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start Writing")
            .accessibilityIdentifier("NewItemBody")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .defaultFocus($titleFocused, true)
        .onChange(of: draft.typeID) {
            if !parents.contains(where: { $0.id == draft.parentID }) { draft.parentID = nil }
            rejected = false
        }
        .onChange(of: draft.title) { rejected = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("NewItemPage")
    }

    private var parents: [Item] { library.creationParentCandidates(typeID: draft.typeID) }

    private func startWriting() {
        guard browser.isCreatingItem else { return }
        guard browser.createDraft(in: library, undoManager: undoManager) != nil else {
            rejected = true
            return
        }
    }
}
