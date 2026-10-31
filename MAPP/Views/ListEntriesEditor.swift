import SwiftUI

/// A list of entries in the inspector (a person's emails, an event's attendees): each entry is a block of its members,
/// edited by kind and format, with its place in the list. The first entry is the main one. Every change writes the
/// whole list back through `ListEntries`, so the entries that were not touched stay as they were, and a list the
/// server refuses is kept in the field with the refusal told, through the row's own refused-write path.
struct ListEntriesEditor: View {
    let shape: ListShape
    let label: String
    let key: String
    let value: PropertyValue?
    let isEditable: Bool
    /// Writes the list (nil unsets it); false where the library refused it.
    let onChange: (PropertyValue?) -> Bool
    /// The entry being added, kept until it holds what the list requires.
    @State private var pending: ListEntries.Entry?
    @State private var notice: String?

    private var entries: [PropertyValue] { ListEntries.entries(of: value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                entryBlock(index: index, entry: entry)
            }
            if let pending {
                block(members: pending, index: nil, isMain: entries.isEmpty)
            }
            if isEditable, pending == nil {
                Button { pending = [:]; notice = nil } label: { Label("Add \(label)", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("ItemListAdd.\(key)")
            }
            if let notice {
                Text(notice).interfaceFont(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ItemListNotice.\(key)")
            }
        }
    }

    @ViewBuilder private func entryBlock(index: Int, entry: PropertyValue) -> some View {
        if let fields = ListEntries.object(entry) {
            block(members: fields, index: index, isMain: index == 0)
        } else {
            // An entry the app cannot read is shown as it is and kept.
            InspectorText(text: ItemValueText.string(entry))
        }
    }

    private func block(members fields: ListEntries.Entry, index: Int?, isMain: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if isEditable {
                HStack(spacing: 6) {
                    if isMain { Text("Main").interfaceFont(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if let index { entryMenu(index) } else {
                        Button("Cancel") { pending = nil; notice = nil }.buttonStyle(.borderless).interfaceFont(.caption)
                    }
                }
                ForEach(shape.members) { member in
                    MemberField(member: member, value: fields[member.key], key: "\(key).\(index.map(String.init) ?? "new").\(member.key)") {
                        commit(member: member.key, to: $0, at: index)
                    }
                }
            } else {
                InspectorText(text: shape.summary(of: fields))
                    .accessibilityIdentifier("ItemListEntry.\(key).\(index ?? 0)")
            }
        }
        .padding(.vertical, 2)
    }

    private func entryMenu(_ index: Int) -> some View {
        Menu {
            if index > 0 { Button("Make Main") { write(ListEntries.makingMain(index, in: value)) } }
            if index > 0 { Button("Move Up") { write(ListEntries.moving(from: index, to: index - 1, in: value)) } }
            if index < entries.count - 1 { Button("Move Down") { write(ListEntries.moving(from: index, to: index + 1, in: value)) } }
            Button("Remove", role: .destructive) { write(ListEntries.removing(at: index, from: value)) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Entry Actions")
        .accessibilityIdentifier("ItemListEntryMenu.\(key).\(index)")
    }

    private func write(_ new: PropertyValue?) {
        notice = nil
        if !onChange(new) { notice = String(localized: "The list could not be saved.") }
    }

    /// Sets one member of an entry, or of the entry being added. Returns whether the member's text is settled: false keeps
    /// the field as typed, with `notice` saying why.
    private func commit(member: String, to new: PropertyValue?, at index: Int?) -> Bool {
        notice = nil
        guard let index else {
            var entry = pending ?? [:]
            entry[member] = new
            if shape.refusal(of: entry) == nil {
                pending = nil
                return onChange(ListEntries.appending(entry, to: value))
            }
            pending = entry
            return true
        }
        guard let fields = ListEntries.object(entries[index]) else { return false }
        var changed = fields
        changed[member] = new
        if let refusal = shape.refusal(of: changed) {
            notice = refusal
            return false
        }
        guard let updated = ListEntries.setting(member, to: new, at: index, in: value) else { return false }
        if !onChange(updated) {
            notice = String(localized: "The list could not be saved.")
            return false
        }
        return true
    }
}

/// One member of an entry, edited by its kind: a menu for a choice, a checkbox for a yes or no, a text field for the
/// rest, committed on return or when it loses focus.
private struct MemberField: View {
    let member: ListShape.Member
    let value: PropertyValue?
    let key: String
    /// Writes the member (nil removes it); false keeps the text as typed.
    let commit: (PropertyValue?) -> Bool
    @State private var text = ""
    @State private var typing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(LocalizedStringKey(member.label)).foregroundStyle(.secondary).interfaceFont(.caption)
                .frame(width: 84, alignment: .leading).lineLimit(1)
            control.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { text = ListShape.editing(value) }
        .onChange(of: value) { _, new in if !focused { text = ListShape.editing(new); typing = false } }
    }

    @ViewBuilder private var control: some View {
        switch member.kind {
        case .choice(let choices):
            let current = value?.string
            Picker(LocalizedStringKey(member.label), selection: Binding {
                current ?? ""
            } set: { _ = commit($0.isEmpty ? nil : .string($0)) }) {
                Text("Not Set").tag("")
                ForEach(choices, id: \.self) { Text(verbatim: ItemTypeInfo.Field.label(ofOption: $0)).tag($0) }
                if let current, !choices.contains(current) { Text(verbatim: current).tag(current) }
            }
            .labelsHidden()
            .accessibilityIdentifier("ItemListMember.\(key)")
        case .boolean:
            Toggle(LocalizedStringKey(member.label), isOn: Binding {
                InspectorFields.isYes(value)
            } set: { _ = commit(.bool($0)) })
            .labelsHidden().toggleStyle(.checkbox)
            .accessibilityIdentifier("ItemListMember.\(key)")
        case .text, .number, .date:
            TextField(LocalizedStringKey(member.label), text: $text, prompt: Text(member.required ? "Required" : "None"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(settle)
                .onChange(of: focused) { if !focused { settle() } }
                .accessibilityIdentifier("ItemListMember.\(key)")
        }
    }

    /// Writes the text as the member's value, or leaves it as typed where it is not one.
    private func settle() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != ListShape.editing(value) else { return }
        guard !trimmed.isEmpty else { _ = commit(nil); return }
        let parsed: PropertyValue?
        switch member.kind {
        case .number(let rule): parsed = PropertyNumber.parse(trimmed, rule: rule).map(PropertyValue.number)
        default: parsed = .string(trimmed)
        }
        guard let parsed, member.accepts(parsed) else {
            _ = commit(.string(trimmed))
            return
        }
        _ = commit(parsed)
    }
}
