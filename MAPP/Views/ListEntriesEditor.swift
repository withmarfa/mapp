import SwiftUI

/// A list of entries in the inspector (a person's emails, an event's attendees): each entry is a block of its members,
/// edited by kind and format, with its place in the list. The first entry is the main one. Every change writes the
/// whole list back through `ListEntries`, so the entries that were not touched stay as they were. What the person is
/// doing to the list, and the text not yet written, live in `editing` (`ListEditing`), so an entry keeps its text
/// while the list changes, and nothing typed is dropped when a row leaves the screen.
struct ListEntriesEditor: View {
    let shape: ListShape
    let label: String
    let key: String
    let value: PropertyValue?
    let isEditable: Bool
    let editing: ListEditing
    /// Whether the library still has a write of the item on its way (`ItemLibrary.isWritingProperties(of:)`).
    var isWriting = false
    /// Writes the list (nil unsets it); false where the library refused it.
    let onChange: (PropertyValue?) -> Bool
    @Environment(\.library) private var library

    var body: some View {
        let rows = editing.rows(of: value, writing: isWriting, marks: marks)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                entryBlock(row, index: index, count: rows.count)
            }
            if let pending = editing.pending {
                block(fields: pending, id: editing.pendingID, index: nil, count: rows.count)
            }
            if isEditable, editing.pending == nil {
                Button { editing.startEntry() } label: { Label("Add Entry", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    // The row's own label names the list beside the button; a spoken one needs it said.
                    .accessibilityLabel("Add Entry to \(label)")
                    .accessibilityIdentifier("ItemListAdd.\(key)")
            }
            if let notice = editing.notice {
                Text(notice).interfaceFont(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ItemListNotice.\(key)")
            }
        }
        // Text typed into an entry that went from the list elsewhere, or given to a refused write whose place is
        // gone, goes back to the person.
        .onChange(of: value, initial: true) { handBackOrphans() }
        .onChange(of: isWriting) { handBackOrphans() }
    }

    private var marks: ListEditing.Marks {
        guard let library else { return ListEditing.Marks() }
        return ListEditing.Marks(
            last: { [weak library] in library?.lastPropertyWrite }, took: { [weak library] in library?.tookPropertyWrite($0) ?? false })
    }

    private func handBackOrphans() {
        if let notices = library?.notices { editing.handBackOrphans(label: label, to: notices) }
    }

    @ViewBuilder private func entryBlock(_ row: ListEditing.Row, index: Int, count: Int) -> some View {
        if let fields = ListEntries.object(row.entry) {
            block(fields: fields, id: row.id, index: index, count: count)
        } else {
            // An entry the app cannot read is shown as it is, and can be moved or removed.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    InspectorText(text: ItemValueText.string(row.entry))
                    Spacer()
                    if isEditable { entryMenu(row.id, index: index, count: count) }
                }
                fault(of: row.entry, index: index)
            }
        }
    }

    private func block(fields: ListEntries.Entry, id: UUID, index: Int?, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if isEditable {
                HStack(spacing: 6) {
                    if index ?? count == 0 { Text("Main").interfaceFont(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if let index { entryMenu(id, index: index, count: count) } else {
                        Button("Cancel") { editing.cancelEntry() }.buttonStyle(.borderless).interfaceFont(.caption)
                    }
                }
                ForEach(shape.members) { member in
                    memberField(member, of: id, holding: fields[member.key], index: index)
                }
                ForEach(fields.keys.filter { shape.member($0) == nil }.sorted(), id: \.self) { undeclared in
                    undeclaredMember(undeclared, holding: fields[undeclared], of: id)
                }
            } else {
                InspectorText(text: shape.summary(of: fields))
                    .accessibilityIdentifier("ItemListEntry.\(key).\(index ?? 0)")
            }
            if let index { fault(of: .object(fields), index: index) }
        }
        .padding(.vertical, 2)
    }

    private func memberField(_ member: ListShape.Member, of id: UUID, holding stored: PropertyValue?, index: Int?) -> some View {
        let slot = ListEditing.Slot(entry: id, member: member.key)
        return MemberField(
            member: member, value: stored, key: "\(key).\(index.map(String.init) ?? "new").\(member.key)",
            text: Binding { editing.text(slot, in: value) } set: { editing.type($0, into: slot, in: value) },
            isConflict: isEditable && editing.conflicts(slot, in: value),
            set: { editing.set(member.key, to: $0, of: id, in: shape, value: value, write: onChange) },
            commit: { overwriting in editing.commit(member, of: id, in: shape, value: value, overwriting: overwriting, write: onChange) },
            discard: { editing.discard(slot, in: value) })
    }

    /// A member the list does not declare, which Marfa refuses the list for: shown as it is, with Remove.
    private func undeclaredMember(_ name: String, holding stored: PropertyValue?, of id: UUID) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: name).foregroundStyle(.secondary).interfaceFont(.caption)
                .frame(width: 84, alignment: .leading).lineLimit(1)
            InspectorText(text: stored.map(ItemValueText.string) ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Remove", systemImage: "minus.circle") {
                editing.set(name, to: nil, of: id, in: shape, value: value, write: onChange)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityIdentifier("ItemListRemoveMember.\(key).\(name)")
        }
    }

    /// Why a stored entry cannot be written as it is, under it.
    @ViewBuilder private func fault(of entry: PropertyValue, index: Int) -> some View {
        if let fault = shape.fault(of: entry) {
            Text(fault).interfaceFont(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ItemListEntryFault.\(key).\(index)")
        }
    }

    private func entryMenu(_ id: UUID, index: Int, count: Int) -> some View {
        Menu {
            if index > 0 { Button("Make Main") { editing.move(id, to: 0, in: shape, value: value, write: onChange) } }
            if index > 0 { Button("Move Up") { editing.move(id, to: index - 1, in: shape, value: value, write: onChange) } }
            if index < count - 1 { Button("Move Down") { editing.move(id, to: index + 1, in: shape, value: value, write: onChange) } }
            Button("Remove", role: .destructive) { editing.remove(id, in: shape, value: value, write: onChange) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Entry Actions")
        .accessibilityIdentifier("ItemListEntryMenu.\(key).\(index)")
    }
}

/// One member of an entry, edited by its kind: a menu for a choice, a checkbox for a yes or no, a text field for the
/// rest, committed on return or when it loses focus. The field shows what was typed until it is written, whatever
/// the list does meanwhile, and what the entry holds otherwise.
private struct MemberField: View {
    let member: ListShape.Member
    let value: PropertyValue?
    let key: String
    @Binding var text: String
    let isConflict: Bool
    /// Sets a choice or a yes or no (nil removes it).
    let set: (PropertyValue?) -> Bool
    /// Writes the typed text, over a change made elsewhere where `overwriting`.
    let commit: (_ overwriting: Bool) -> Bool
    let discard: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(LocalizedStringKey(member.label)).foregroundStyle(.secondary).interfaceFont(.caption)
                    .frame(width: 84, alignment: .leading).lineLimit(1)
                control.frame(maxWidth: .infinity, alignment: .leading)
            }
            if isConflict { conflictNotice }
        }
    }

    @ViewBuilder private var control: some View {
        switch member.kind {
        case .choice(let choices):
            let current = value?.string
            Picker(LocalizedStringKey(member.label), selection: Binding {
                current ?? ""
            } set: { _ = set($0.isEmpty ? nil : .string($0)) }) {
                Text("Not Set").tag("")
                ForEach(choices, id: \.self) { Text(verbatim: ItemTypeInfo.Field.label(ofOption: $0)).tag($0) }
                if let current, !choices.contains(current) { Text(verbatim: current).tag(current) }
            }
            .labelsHidden()
            .accessibilityIdentifier("ItemListMember.\(key)")
        case .boolean:
            Toggle(LocalizedStringKey(member.label), isOn: Binding {
                InspectorFields.isYes(value)
            } set: { _ = set(.bool($0)) })
            .labelsHidden().toggleStyle(.checkbox)
            .accessibilityIdentifier("ItemListMember.\(key)")
        case .text, .number, .date:
            TextField(LocalizedStringKey(member.label), text: $text, prompt: Text(member.required ? "Required" : "None"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { _ = commit(false) }
                .onChange(of: focused) { if !focused { _ = commit(false) } }
                .onExitCommand { discard(); focused = false }
                .accessibilityIdentifier("ItemListMember.\(key)")
        }
    }

    private var conflictNotice: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("This value changed while you were editing. Your edit hasn’t been saved.")
                .interfaceFont(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Keep My Edit") { _ = commit(true) }
                    .accessibilityIdentifier("ItemListKeepEdit.\(key)")
                Button("Use Current Value") { discard() }
                    .accessibilityIdentifier("ItemListUseCurrent.\(key)")
            }
            .buttonStyle(.borderless)
            .interfaceFont(.caption)
        }
    }
}
