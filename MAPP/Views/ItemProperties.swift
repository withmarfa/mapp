import Marfa
import SwiftUI

/// One property of an item as a row of the inspector. The value of an item's property opens in a panel under it
/// (`ValueEditPresenter`), as it does on the page: a text, a number, a choice, a status, a date, a list of words and a
/// list of people. A yes/no is a checkbox. A row for a value no item holds yet (a form's) types a text or a number into
/// a borderless field that looks like plain text until it is used; it keeps unfinished input until it is committed, and
/// a change made elsewhere meanwhile is never written over silently.
struct ItemPropertyRow: View {
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    let definition: ItemTypeInfo.Field
    let value: PropertyValue?
    let isEditable: Bool
    let onChange: (PropertyValue?) -> Bool
    /// The item the value belongs to, which the panel under it reads the value from and closes with. A row for a value
    /// no item holds yet (quick add's, a change of type's) has none.
    var item: ItemID? = nil
    var retainedDraft: ItemPropertyDraft? = nil
    /// A row the person has just added opens ready to edit: a text or number field takes the keyboard and a value
    /// that opens a panel shows it. A yes/no waits for a click.
    var startsEditing = false
    /// Whether the row writes or hands back what was typed when it leaves the screen. A row whose draft belongs to a
    /// window (the inspector's) or to a sheet that may be cancelled leaves that to its owner: a section folded, or a
    /// sheet closed, must not raise "Property Not Saved" or put text on the clipboard.
    var handsOffOnLeave = true
    /// Whether the page shows this property too, and what changes it; nil offers no choice.
    var shownOnPage = true
    var onShowOnPage: ((Bool) -> Void)?
    /// Whether the library still has a write of the item's properties on its way, which a list of entries waits for.
    var isWriting = false
    @Environment(\.interfaceTextSize) private var textSize
    @Environment(\.openURL) private var openURL
    @Environment(\.library) private var library
    @Environment(\.undoManager) private var undoManager
    @State private var localDraft = ItemPropertyDraft()
    @State private var anchor = ValueEditAnchorBox()
    /// Whether a link's text is being edited, as opposed to followed.
    @State private var editing = false
    /// A status field's value has the status's ring.
    private var isStatus: Bool { definition.isStatus }
    @FocusState private var isFocused: Bool
    private var input: ItemPropertyDraft { retainedDraft ?? localDraft }

    var body: some View {
        InspectorRow(fieldLabel: definition.label) {
            VStack(alignment: .leading, spacing: 4) {
                core.background(ValueEditAnchor(box: anchor))
                if let invalidValue {
                    Text(invalidValue).interfaceFont(.caption).foregroundStyle(.orange)
                }
                if isEditable && input.conflicts(with: currentText) { conflictNotice }
                if input.rejected, !isList { rejectedNotice }
                if lostEdit { lostEditNotice }
            }
        }
        .onNameTap(panelKind != nil && isEditable ? { openEditor() } : nil)
        .contextMenu { menu }
        .onAppear {
            input.field = definition
            if !input.isDirty { seed(value) }
        }
        .task { if startsEditing { await beginEditing() } }
        // The action may run on an earlier copy of this view, so it takes the value from the change itself.
        .onChange(of: value) { _, value in if !input.isDirty { seed(value) } }
        .onChange(of: isFocused) {
            guard !isFocused else { return }
            commit()
            if !input.isDirty { editing = false }
        }
        .onDisappear(perform: leave)
    }

    // MARK: Value

    @ViewBuilder private var core: some View {
        if case .list(let shape) = definition.kind {
            // The list tells its own refusals, beside the entry they are about.
            VStack(alignment: .leading, spacing: 8) {
                ListEntriesEditor(
                    shape: shape, label: definition.label, key: definition.key, value: value, isEditable: isEditable,
                    editing: input.list, isWriting: isWriting, onChange: onChange)
                if isEditable, editKind != nil {
                    Button { openEditor() } label: { Label("Add Person…", systemImage: "person.badge.plus") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Add Person to \(definition.label)")
                        .accessibilityIdentifier("ItemListAddPerson.\(definition.key)")
                }
            }
        } else if definition.kind == .boolean {
            checkbox
        } else if isEditable, let kind = panelKind {
            // A link is followed from its text and changed from its name.
            if link != nil { linkText } else { editorButton(kind) }
        } else if isEditable {
            switch definition.kind {
            case .text, .number:
                if link != nil, !editing, !input.isDirty { linkText } else { textField }
            default: plain
            }
        } else if link != nil {
            linkText
        } else {
            plain
        }
    }

    /// A web or mail address as a link, in the accent color. It opens on a click; an editable one is changed from its
    /// context menu.
    @ViewBuilder private var linkText: some View {
        if let link {
            let hint: LocalizedStringKey = link.scheme == "mailto" ? "Writes to this address" : "Opens this address"
            Button { openURL(link) } label: {
                InspectorText(text: shownText, style: AnyShapeStyle(Color.accentColor))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .accessibilityLabel(LocalizedStringKey(definition.label))
            .accessibilityValue(shownText)
            .accessibilityHint(hint)
            .accessibilityIdentifier("ItemProperty.\(definition.key)")
        }
    }

    /// A value nothing here changes, read as a Details row is.
    @ViewBuilder private var plain: some View {
        if definition.kind.isDate, let dateText {
            InspectorText(text: dateText, keepsOneLine: true, endsAtTrailingEdge: true)
                .accessibilityIdentifier("ItemProperty.\(definition.key)")
        } else if isStatus, let text = value?.string {
            statusLabel(Text(verbatim: ItemTypeInfo.Field.label(ofOption: text)))
                .accessibilityIdentifier("ItemProperty.\(definition.key)")
        } else if case .choice = definition.kind, let text = value?.string {
            InspectorText(text: ItemTypeInfo.Field.label(ofOption: text), endsAtTrailingEdge: true)
                .accessibilityIdentifier("ItemProperty.\(definition.key)")
        } else if !shownText.isEmpty {
            InspectorText(text: shownText, endsAtTrailingEdge: true).accessibilityIdentifier("ItemProperty.\(definition.key)")
        }
    }

    private var currentText: String { value.map(ItemValueText.editing) ?? "" }

    private var isList: Bool { definition.kind.isList }

    /// What the row reads at rest: the draft while there is one the item can take, else the stored value. An item that
    /// can no longer be edited shows what it holds, not what was typed for it.
    private var shownText: String {
        if definition.kind.isDate, let dateText { return dateText }
        return input.isDirty && isEditable ? input.text : currentText
    }

    private var statusMark: PageHeader.Mark { .init(group: value?.string.flatMap(definition.statusGroup(of:))) }

    /// The status's ring, then its word.
    private func statusLabel(_ text: Text?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            StatusMark(mark: statusMark, size: 10 * InterfaceStyle.scale(for: textSize))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            if let text { text } else { InspectorPlaceholder(text: "Choose") }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// A value at rest in the row that opens its panel: its text, cut at `lines`, or what stands for none.
    @ViewBuilder private func choiceLabel(_ text: Text?, placeholder: LocalizedStringKey, lines: Int) -> some View {
        if isStatus {
            statusLabel(text)
        } else if let text {
            text.lineLimit(lines).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
        } else {
            InspectorPlaceholder(text: placeholder)
        }
    }

    /// A yes or no is the system's checkbox; a value that is not set reads as unchecked, and Clear in the menu unsets it.
    private var checkbox: some View {
        Toggle(isOn: Binding { InspectorFields.isYes(value) } set: { input.rejected = !onChange(.bool($0)) }) {
            Text(LocalizedStringKey(definition.label))
        }
        .labelsHidden()
        .toggleStyle(.checkbox)
        .disabled(!isEditable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(LocalizedStringKey(definition.label))
        .accessibilityIdentifier("ItemProperty.\(definition.key)")
    }

    // MARK: Menu

    @ViewBuilder private var menu: some View {
        if let link {
            Button("Open") { openURL(link) }.accessibilityIdentifier("ItemPropertyOpen.\(definition.key)")
        }
        if value != nil, definition.kind != .boolean {
            Button("Copy") { InspectorPasteboard.copy(currentText) }
                .accessibilityIdentifier("ItemPropertyCopy.\(definition.key)")
        }
        if isEditable, link != nil {
            Button("Edit") { panelKind == nil ? beginTextEdit() : openEditor() }.accessibilityIdentifier("ItemPropertyEdit.\(definition.key)")
        }
        if onShowOnPage != nil || canClear { Divider() }
        if let onShowOnPage { ShowOnPageMenu(isShown: shownOnPage, onChange: onShowOnPage) }
        if canClear {
            Button("Clear") { clear() }.accessibilityIdentifier("ItemPropertyClear")
        }
    }

    private var canClear: Bool {
        guard isEditable, InspectorFields.hasValue(value) else { return false }
        if case .other = definition.kind { return false }
        return true
    }

    private func clear() {
        if isList {
            if !onChange(nil) { input.list.notice = String(localized: "The list could not be saved.") }
            return
        }
        input.rejected = !onChange(nil)
        if !input.rejected { input.discard(toMatch: "") ; editing = false }
    }

    // MARK: Notices

    private var conflictNotice: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("This value changed while you were editing. Your edit hasn’t been saved.")
                .interfaceFont(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Keep My Edit") { commit(overwriting: true) }
                    .accessibilityIdentifier("ItemPropertyKeepEdit.\(definition.key)")
                Button("Use Current Value") { input.discard(toMatch: currentText); editing = false }
                    .accessibilityIdentifier("ItemPropertyUseCurrent.\(definition.key)")
            }
            .buttonStyle(.borderless)
            .interfaceFont(.caption)
        }
    }

    /// Typed text an item that can no longer be edited cannot take. The row shows what the item holds; the text waits
    /// for the hand-off when the row goes, which gives it back.
    private var lostEdit: Bool {
        !isEditable && input.isDirty && input.text != currentText && input.text != input.base
    }

    private var lostEditNotice: some View {
        Text("This item can no longer be edited. Your change wasn’t saved.")
            .interfaceFont(.caption).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("ItemPropertyNotEditable.\(definition.key)")
    }

    private var rejectedNotice: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if definition.kind == .number, let requirement = definition.numberRule.requirement,
                   PropertyNumber.parse(input.text, rule: definition.numberRule) == nil {
                    Text(requirement)
                } else {
                    Text("The value could not be saved. Your input has been kept.")
                }
            }
            .interfaceFont(.caption)
            .foregroundStyle(.red)
            Button("Discard Changes") { input.discard(toMatch: currentText); editing = false }
                .interfaceFont(.caption)
        }
    }

    // MARK: Editing

    private func beginTextEdit() {
        guard isEditable else { return }
        if !input.isDirty { seed(value) }
        editing = true
        Task { await focus() }
    }

    private func focus() async {
        // The field for a link, or for a value of the person's own, is in the tree one turn after the row asks for it.
        await Task.yield()
        isFocused = true
    }

    private func beginEditing() async {
        await Task.yield()
        if panelKind != nil {
            openEditor()
            return
        }
        switch definition.kind {
        case .text, .number: isFocused = true
        default: break
        }
    }

    // MARK: Panel

    /// How the value is edited in a panel under it, or nil where it is edited in the row.
    private var editKind: ValueEditKind? { ValueEditKind(field: definition) }

    /// The panel the value opens in. A row for a value no item holds yet types a text or a number into the row, since a
    /// panel writes what was typed to its item.
    private var panelKind: ValueEditKind? { editKind.flatMap { item == nil && $0.isTyped ? nil : $0 } }

    private func openEditor() {
        guard isEditable, let kind = panelKind, let library, let view = anchor.view else { return }
        let request = ValueEditRequest(kind: kind, library: library, item: item, heldValue: value, undoManager: undoManager, write: onChange)
        ValueEditPresenter.shared.present(request, anchor: view)
    }

    /// The value at rest, which a click opens in its panel. It reads as a person writes it, and changes only through the
    /// panel, so what is stored is always one of the forms Marfa takes.
    private func editorButton(_ kind: ValueEditKind) -> some View {
        let text = restingText
        let hint: LocalizedStringKey = switch kind {
        case .date: "Opens a calendar"
        case .status, .choice: "Opens a list of choices"
        case .words: "Opens a list of words to add to and remove from"
        default: "Opens a field to type in"
        }
        let placeholder: LocalizedStringKey = kind.closesOnChoice ? "Choose" : "None"
        return Button { openEditor() } label: {
            choiceLabel(text.map { Text(verbatim: $0) }, placeholder: placeholder, lines: kind.isTyped || isWords ? 3 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(LocalizedStringKey(definition.label))
        .accessibilityValue(text.map { Text(verbatim: $0) } ?? Text("Not Set"))
        .accessibilityHint(hint)
        .accessibilityIdentifier("ItemProperty.\(definition.key)")
    }

    private var isWords: Bool { definition.kind == .words }

    /// What the value reads at rest, or nil where there is none.
    private var restingText: String? {
        switch definition.kind {
        case .date: dateText
        case .status, .choice: value?.string.map { ItemTypeInfo.Field.label(ofOption: $0) }
        case .words: ListEntries.entries(of: value).compactMap(\.string).joined(separator: ", ").nilIfEmpty
        default: currentText.nilIfEmpty
        }
    }

    /// Where the value links to, if it is a web or mail address.
    private var link: URL? { InspectorFields.link(of: definition, value: value) }

    /// A date as the person reads it; a value that is not one keeps its text, and the row warns about it.
    private var dateText: String? {
        guard let text = value?.string, !text.isEmpty else { return nil }
        return ItemDate.parse(text)?.text(format: dateFormat) ?? text
    }

    /// The field that edits a value: the system's borderless text field, which reads as plain text at rest and shows
    /// its focus ring while it is in use. At rest a value of words is cut at three lines and a single word, as a
    /// link or an identifier is, at one; in use it grows.
    private var textField: some View {
        let isNumber = definition.kind == .number
        let text = input.isDirty ? input.text : currentText
        let token = InspectorText.isToken(text)
        return TextField(LocalizedStringKey(definition.label), text: Binding {
            input.isDirty ? input.text : currentText
        } set: { typed in
            guard typed != (input.isDirty ? input.text : currentText) else { return }
            if !input.isDirty { input.base = currentText }
            input.text = typed
            input.isDirty = true
            input.rejected = false
        }, prompt: Text("None"), axis: isNumber ? .horizontal : .vertical)
        .labelsHidden()
        .textFieldStyle(.plain)
        .multilineTextAlignment(.leading)
        .lineLimit(isNumber ? 1...1 : isFocused ? 1...12 : token ? 1...1 : 1...3)
        .truncationMode(token ? .middle : .tail)
        .focused($isFocused)
        .onSubmit { commit() }
        .onExitCommand { input.discard(toMatch: currentText); editing = false; isFocused = false }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(isFocused ? "" : String(text.prefix(600)))
        .accessibilityIdentifier("ItemProperty.\(definition.key)")
    }

    private var invalidValue: String? {
        guard let value else { return nil }
        let valid: Bool
        switch (definition.kind, value) {
        case (.text, .string), (.boolean, .bool), (.number, .number): valid = true
        case (.choice(let choices), .string(let text)): valid = choices.contains(text)
        case (.status, .string(let text)): valid = definition.statusGroup(of: text) != nil
        case (.date, .string): valid = definition.kind.accepts(value)
        case (.other, _): valid = true
        case (.list, _), (.words, _): valid = definition.accepts(value)
        default: valid = false
        }
        return valid ? nil : String(localized: "Unrecognized value: \(ItemValueText.string(value)). It is preserved until you replace it.")
    }

    private func seed(_ value: PropertyValue?) {
        input.text = value.map(ItemValueText.editing) ?? ""
        input.base = input.text
        input.rejected = false
    }

    /// A row that owns its draft leaves nothing the person typed behind: it is written, or handed back through
    /// `Notices`, which puts it on the clipboard. Any other row only writes what it can, since its owner decides
    /// whether the draft is gone for good.
    private func leave() {
        guard handsOffOnLeave, let library else {
            commit()
            return
        }
        if case .list(let shape) = definition.kind {
            input.list.leave(shape, label: definition.label, value: value, isEditable: isEditable, write: onChange, to: library.notices)
            return
        }
        input.handOff(
            label: definition.label, as: definition.kind, rule: definition.numberRule, current: currentText,
            isEditable: isEditable, write: onChange, to: library.notices)
        editing = false
    }

    private func commit(overwriting: Bool = false) {
        guard isEditable else { return }
        switch input.commit(as: definition.kind, rule: definition.numberRule, current: currentText, overwriting: overwriting) {
        case .unchanged, .conflict:
            break
        case .alreadyCurrent:
            // The edit was undone by hand, or the item already holds it; the item's own text stands.
            input.discard(toMatch: currentText)
        case .invalid, .outOfRange:
            input.rejected = true
        case .write(let written):
            input.rejected = !onChange(written)
            if !input.rejected { input.isDirty = false }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Displaying unfamiliar values is intentionally independent of their editable schema.
nonisolated enum ItemValueText {
    static func string(_ value: PropertyValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let value): value ? "true" : "false"
        case .number(let value): NSDecimalNumber(decimal: value).stringValue
        case .string(let value): value
        case .array(let values): values.map(string).joined(separator: ", ")
        case .object(let fields): fields.keys.sorted().map { "\($0): \(string(fields[$0]!))" }.joined(separator: ", ")
        }
    }

    /// A value as the text field that edits it holds it: a number in the person's locale, as `PropertyNumber` reads it.
    static func editing(_ value: PropertyValue) -> String {
        if case .number(let number) = value { return PropertyNumber.editing(number) }
        return string(value)
    }
}

#if DEBUG
#Preview("Property Controls") {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SampleLibrary.catalogue.itemTypes[TypeID("core.task")]?.fields ?? []) { definition in
                ItemPropertyRow(definition: definition, value: definition.isStatus ? .string("in_progress") : nil,
                                isEditable: true, onChange: { _ in true })
            }
            ItemPropertyRow(definition: .init(key: "occurred_at", label: "Decided", kind: .date(includesTime: false), declaredBy: TypeID("aic.decision")),
                            value: .string("2026-10-02"), isEditable: true, onChange: { _ in true })
        }
        .padding(16)
    }
    .interfaceTextStyle()
    .frame(width: 300, height: 440)
}
#endif
