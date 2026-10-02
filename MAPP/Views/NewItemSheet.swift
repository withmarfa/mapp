import SwiftUI

struct NewItemSheet: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    let browser: Browser
    @State private var typeID = "core.note"
    @State private var title = ""
    @State private var parentID: UUID?
    @State private var rejected = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Item").font(.title2.bold())
            Form {
                Picker("Type", selection: $typeID) {
                    ForEach(WorkbenchSchema.types) { type in Text(LocalizedStringKey(type.label)).tag(type.id) }
                }
                .accessibilityIdentifier("NewItemType")
                TextField("Title", text: $title)
                    .focused($titleFocused)
                    .accessibilityIdentifier("NewItemTitle")
                Picker("Parent", selection: $parentID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(parents) { item in Text(item.title).tag(Optional(item.id)) }
                }
                .accessibilityIdentifier("NewItemParent")
            }
            .formStyle(.grouped)
            Text("You can edit the item’s properties and relationships in Details after creating it.")
                .font(.callout).foregroundStyle(.secondary)
            if rejected {
                Text("The item could not be created. Check its title and parent, then try again.")
                    .font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("NewItemCreate")
            }
        }
        .padding(20)
        .frame(width: 440)
        .defaultFocus($titleFocused, true)
        .onChange(of: typeID) { if !parents.contains(where: { $0.id == parentID }) { parentID = nil } }
        .accessibilityIdentifier("NewItemSheet")
    }

    private var parents: [AppItem] {
        library.creationParentCandidates(typeID: typeID)
    }

    private func create() {
        guard let note = library.createItem(typeID: typeID, title: title, parentID: parentID, in: browser.item, undoManager: undoManager) else {
            rejected = true
            return
        }
        browser.searchText = ""
        browser.isSearchExpanded = false
        browser.sidebarItem = .allNotes
        browser.selection = [note.id]
        browser.focusRequest = .page
        dismiss()
    }
}
