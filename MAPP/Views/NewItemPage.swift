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
                .padding(.top, 16)
        }
        // Match the editor's opaque backing instead of the window's tinted surface.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Untitled", text: $draft.title)
                .font(.system(size: CGFloat(style.textSize) * 1.9, weight: .bold))
                .textFieldStyle(.plain)
                .foregroundStyle(Color(nsColor: .textColor))
                .focused($titleFocused)
                .onSubmit { startWriting() }
                .accessibilityLabel("Title")
                .accessibilityIdentifier("NewItemTitle")
            ItemPinLayout {
                Menu {
                    ForEach(creatableTypes) { type in
                        Button { draft.typeID = type.id.rawValue } label: {
                            if draft.typeID == type.id.rawValue {
                                Label(type.label, systemImage: "checkmark")
                            } else {
                                Label(type.label, systemImage: type.symbol)
                            }
                        }
                    }
                } label: {
                    ItemPinLabel(title: Text(chosenType?.label ?? String(localized: "Type")),
                                 systemImage: chosenType?.symbol ?? TypeSymbol.fallback)
                }
                .itemPinMenuStyle()
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
                    ItemPinLabel(title: Text(parents.first { $0.id == draft.parentID }?.title ?? String(localized: "Parent")),
                                 systemImage: "folder", isEmpty: draft.parentID == nil)
                }
                .itemPinMenuStyle(isEmpty: draft.parentID == nil)
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
        .onChange(of: browser.focusRequest, initial: true) {
            if browser.isCreatingItem, browser.focusRequest == .page {
                titleFocused = true
                browser.focusRequest = nil
            }
        }
        .onChange(of: draft.typeID, initial: true) {
            draft.validateParent(in: library)
            rejected = false
        }
        .onChange(of: draft.title) { rejected = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("NewItemPage")
    }

    /// Every kind of item the library can make, by name.
    private var creatableTypes: [ItemTypeOption] { library.creatableTypes }

    private var chosenType: ItemTypeOption? { creatableTypes.first { $0.id.rawValue == draft.typeID } }

    private var parents: [Item] { library.creationParentCandidates(typeID: draft.typeID) }

    private func startWriting() {
        guard browser.isCreatingItem else { return }
        guard browser.createDraft(in: library, undoManager: undoManager) != nil else {
            rejected = true
            return
        }
    }
}
