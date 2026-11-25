import SwiftUI

/// A list of entries (a person's emails and phone numbers, an event's attendees' answers): each entry is a block of its
/// members, each in a row with its name in a column beside it, edited by kind. The first entry is the main one, which the
/// page's row shows with how many more there are. Every change writes the whole list back through `ListEntries`, so the
/// entries that were not touched stay as they were. What the person is doing to the list, and the text not yet written,
/// live in `editing` (`ListEditing`), so an entry keeps its text while the list changes and nothing typed is dropped when
/// a row leaves the screen. The value panel under an entries row holds this (`EntriesPanelContent`), and so does a form
/// that has no item to open a panel on yet.
struct EntriesEditor: View {
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
    @Environment(\.interfaceTextSize) private var textSize

    private var scale: CGFloat { InterfaceStyle.scale(for: textSize) }

    var body: some View {
        let rows = editing.rows(of: value, shape: shape, writing: isWriting, marks: marks)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.vertical, 4 * scale) }
                entryBlock(row, index: index, count: rows.count)
            }
            if let pending = editing.pending {
                if !rows.isEmpty { Divider().padding(.vertical, 4 * scale) }
                block(fields: pending, id: editing.pendingID, index: nil, count: rows.count)
            }
            if isEditable, editing.pending == nil {
                if !rows.isEmpty { Divider().padding(.vertical, 4 * scale) }
                addRow
            }
            if let notice = editing.notice {
                Text(notice)
                    .font(.system(size: 11 * scale)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8 * scale).padding(.top, 4 * scale)
                    .accessibilityIdentifier("ItemListNotice.\(key)")
            }
        }
        .font(.system(size: ValueEditMetrics.textSize * scale))
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

    private var addRow: some View {
        Button { editing.startEntry() } label: {
            HStack(spacing: 8 * scale) {
                Image(systemName: "plus").font(.system(size: 11 * scale)).foregroundStyle(.secondary).frame(width: 14 * scale)
                Text("Add Entry")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8 * scale)
            .frame(height: ValueEditMetrics.rowHeight * scale)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The row's own label names the list beside the button; a spoken one needs it said.
        .accessibilityLabel("Add Entry to \(label)")
        .accessibilityIdentifier("ItemListAdd.\(key)")
    }

    @ViewBuilder private func entryBlock(_ row: ListEditing.Row, index: Int, count: Int) -> some View {
        if let fields = ListEntries.object(row.entry) {
            block(fields: fields, id: row.id, index: index, count: count)
        } else {
            // An entry the app cannot read is shown as it is, and can be moved or removed.
            VStack(alignment: .leading, spacing: 2 * scale) {
                HStack(spacing: 6 * scale) {
                    Text(verbatim: ItemValueText.string(row.entry)).lineLimit(2).truncationMode(.tail)
                    Spacer(minLength: 0)
                    if isEditable { entryMenu(row.id, index: index, count: count) }
                }
                .padding(.horizontal, 8 * scale)
                fault(of: row.entry, index: index)
            }
        }
    }

    private func block(fields: ListEntries.Entry, id: UUID, index: Int?, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditable {
                HStack(spacing: 6 * scale) {
                    if (index ?? count) == 0 {
                        Text("Main").font(.system(size: 11 * scale, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let index { entryMenu(id, index: index, count: count) } else {
                        Button("Cancel") { editing.cancelEntry() }.appButton(.secondary, size: .small)
                    }
                }
                .padding(.horizontal, 8 * scale)
                .frame(height: 22 * scale)
                ForEach(shape.members) { member in
                    memberField(member, of: id, holding: fields[member.key], index: index)
                }
                ForEach(fields.keys.filter { shape.member($0) == nil }.sorted(), id: \.self) { undeclared in
                    undeclaredMember(undeclared, holding: fields[undeclared], of: id)
                }
            } else {
                Text(verbatim: shape.summary(of: fields))
                    .padding(.horizontal, 8 * scale)
                    .frame(minHeight: ValueEditMetrics.rowHeight * scale, alignment: .leading)
                    .accessibilityIdentifier("ItemListEntry.\(key).\(index ?? 0)")
            }
            if let index { fault(of: .object(fields), index: index) }
        }
    }

    private func memberField(_ member: ListShape.Member, of id: UUID, holding stored: PropertyValue?, index: Int?) -> some View {
        let slot = ListEditing.Slot(entry: id, member: member.key)
        return MemberField(
            member: member, value: stored, key: "\(key).\(index.map(String.init) ?? "new").\(member.key)", scale: scale,
            text: Binding { editing.text(slot, in: value) } set: { editing.type($0, into: slot, in: value) },
            isConflict: isEditable && editing.conflicts(slot, in: value),
            set: { editing.set(member.key, to: $0, of: id, in: shape, value: value, write: onChange) },
            commit: { overwriting in editing.commit(member, of: id, in: shape, value: value, overwriting: overwriting, write: onChange) },
            discard: { editing.discard(slot, in: value) })
    }

    /// A member the list does not declare, which Marfa refuses the list for: shown as it is, with Remove.
    private func undeclaredMember(_ name: String, holding stored: PropertyValue?, of id: UUID) -> some View {
        HStack(spacing: 8 * scale) {
            Text(verbatim: name).font(.system(size: 12 * scale)).foregroundStyle(.secondary).lineLimit(1)
                .frame(width: MemberField.labelWidth * scale, alignment: .leading)
            Text(verbatim: stored.map(ItemValueText.string) ?? "").lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Button("Remove", systemImage: "minus") {
                editing.set(name, to: nil, of: id, in: shape, value: value, write: onChange)
            }
            .labelStyle(.iconOnly)
            .appButton(.secondary, size: .small, icon: true)
            .help("Remove")
            .accessibilityIdentifier("ItemListRemoveMember.\(key).\(name)")
        }
        .padding(.horizontal, 8 * scale)
        .frame(height: ValueEditMetrics.rowHeight * scale)
    }

    /// Why a stored entry cannot be written as it is, under it.
    @ViewBuilder private func fault(of entry: PropertyValue, index: Int) -> some View {
        if let fault = shape.fault(of: entry) {
            Text(fault).font(.system(size: 11 * scale)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8 * scale)
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
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .appButton(.secondary, size: .small, icon: true)
        .fixedSize()
        .accessibilityLabel("Entry Actions")
        .accessibilityIdentifier("ItemListEntryMenu.\(key).\(index)")
    }
}

/// One member of an entry in its row, its name in a column and its control beside it: a menu for a choice, a switch for a
/// yes or no, a field for the rest, committed on return or when it loses focus. The field shows what was typed until it is
/// written, whatever the list does meanwhile, and what the entry holds otherwise.
private struct MemberField: View {
    static let labelWidth: CGFloat = 72

    let member: ListShape.Member
    let value: PropertyValue?
    let key: String
    let scale: CGFloat
    @Binding var text: String
    let isConflict: Bool
    /// Sets a choice or a yes or no (nil removes it).
    let set: (PropertyValue?) -> Bool
    /// Writes the typed text, over a change made elsewhere where `overwriting`.
    let commit: (_ overwriting: Bool) -> Bool
    let discard: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8 * scale) {
                Text(LocalizedStringKey(member.label))
                    .font(.system(size: 12 * scale)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: Self.labelWidth * scale, alignment: .leading)
                control.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8 * scale)
            .frame(height: ValueEditMetrics.rowHeight * scale)
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
            .fixedSize()
            .accessibilityIdentifier("ItemListMember.\(key)")
        case .boolean:
            Toggle(LocalizedStringKey(member.label), isOn: Binding {
                InspectorFields.isYes(value)
            } set: { _ = set(.bool($0)) })
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
            .accessibilityIdentifier("ItemListMember.\(key)")
        case .text, .number, .date:
            TextField(LocalizedStringKey(member.label), text: $text, prompt: Text(member.required ? "Required" : "Empty"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { _ = commit(false) }
                .onChange(of: focused) { if !focused { _ = commit(false) } }
                .onExitCommand { discard(); focused = false }
                .padding(.horizontal, 7 * scale)
                .frame(height: 22 * scale)
                .background(ChipLooks.current.chipWash(for: scheme), in: .rect(cornerRadius: 7 * scale, style: .continuous))
                .appFocusRing(.rect(cornerRadius: 7 * scale, style: .continuous), isFocused: focused)
                .accessibilityIdentifier("ItemListMember.\(key)")
        }
    }

    /// A conflict is a question, so it has no red: what happened and what it means, with Keep My Edit the main answer.
    private var conflictNotice: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            VStack(alignment: .leading, spacing: 1 * scale) {
                Text(verbatim: ValueEditModel.conflictQuestion)
                Text(verbatim: ValueEditModel.conflictConsequence).foregroundStyle(.secondary)
            }
            .font(.system(size: 11 * scale))
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6 * scale) {
                Button("Keep My Edit") { _ = commit(true) }
                    .appButton(.primary, size: .small)
                    .accessibilityIdentifier("ItemListKeepEdit.\(key)")
                Button("Use Current Value") { discard() }
                    .appButton(.secondary, size: .small)
                    .accessibilityIdentifier("ItemListUseCurrent.\(key)")
            }
        }
        .padding(.horizontal, 8 * scale)
        .padding(.bottom, 4 * scale)
    }
}
