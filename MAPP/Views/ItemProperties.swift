import SwiftUI

/// One property of an item as a row of the inspector, drawn with the system's own controls so they behave as they do
/// everywhere else: a text or number value is a borderless text field that looks like plain text until it is used, a
/// choice is a pop-up menu, a yes/no is a checkbox and a date opens a calendar. Each row keeps unfinished input until
/// it is committed; unrelated inspector updates do not replace it, and a change made elsewhere meanwhile is never
/// written over silently.
struct ItemPropertyRow: View {
    let definition: ItemTypeInfo.Field
    let value: PropertyValue?
    let isEditable: Bool
    let onChange: (PropertyValue?) -> Bool
    var retainedDraft: ItemPropertyDraft? = nil
    /// A row the person has just added opens ready to edit: a text or number field takes the keyboard and a date
    /// shows its calendar. A menu cannot be opened from code, so a choice reads "Choose" and a yes/no waits for a
    /// click.
    var startsEditing = false
    /// Whether the row writes or hands back what was typed when it leaves the screen. A row whose draft belongs to a
    /// window (the inspector's) or to a sheet that may be cancelled leaves that to its owner: a section folded, or a
    /// sheet closed, must not raise "Property Not Saved" or put text on the clipboard.
    var handsOffOnLeave = true
    /// Whether the page shows this property too, and what changes it; nil offers no choice.
    var shownOnPage = true
    var onShowOnPage: ((Bool) -> Void)?
    @Environment(\.interfaceTextSize) private var textSize
    @Environment(\.openURL) private var openURL
    @Environment(\.library) private var library
    @State private var localDraft = ItemPropertyDraft()
    @State private var choosingDate = false
    /// Whether a link's text is being edited, as opposed to followed.
    @State private var editing = false
    /// A status field's value has the status's ring.
    private var isStatus: Bool { definition.isStatus }
    @FocusState private var isFocused: Bool
    private var input: ItemPropertyDraft { retainedDraft ?? localDraft }

    var body: some View {
        InspectorRow(fieldLabel: definition.displayLabel) {
            VStack(alignment: .leading, spacing: 4) {
                core
                if let invalidValue {
                    Text(invalidValue).interfaceFont(.caption).foregroundStyle(.orange)
                }
                if isEditable && input.conflicts(with: currentText) { conflictNotice }
                if input.rejected, !isList { rejectedNotice }
                if lostEdit { lostEditNotice }
            }
        }
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
            ListEntriesEditor(
                shape: shape, label: definition.displayLabel, key: definition.key, value: value, isEditable: isEditable,
                editing: input.list, onChange: onChange)
        } else if definition.kind == .boolean {
            checkbox
        } else if isEditable {
            switch definition.kind {
            case .choice, .status: choiceMenu()
            case .date: dateButton
            case .text, .number:
                if link != nil, !editing, !input.isDirty { linkText } else { textField }
            case .other, .list: plain
            case .boolean: EmptyView()
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
            .accessibilityLabel(LocalizedStringKey(definition.displayLabel))
            .accessibilityValue(shownText)
            .accessibilityHint(hint)
            .accessibilityIdentifier("ItemProperty.\(definition.key)")
        }
    }

    /// A value nothing here changes, read as a Details row is.
    @ViewBuilder private var plain: some View {
        if definition.kind.isDate, let dateText {
            InspectorText(text: dateText, keepsOneLine: true).accessibilityIdentifier("ItemProperty.\(definition.key)")
        } else if isStatus, let text = value?.string {
            statusLabel(Text(verbatim: ItemTypeInfo.Field.label(ofOption: text)))
                .accessibilityIdentifier("ItemProperty.\(definition.key)")
        } else if case .choice = definition.kind, let text = value?.string {
            InspectorText(text: ItemTypeInfo.Field.label(ofOption: text)).accessibilityIdentifier("ItemProperty.\(definition.key)")
        } else if !shownText.isEmpty {
            InspectorText(text: shownText).accessibilityIdentifier("ItemProperty.\(definition.key)")
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

    /// A choice or a date at rest: its text, or what stands for none.
    @ViewBuilder private func choiceLabel(_ text: Text?, placeholder: LocalizedStringKey, oneLine: Bool = false) -> some View {
        if isStatus {
            statusLabel(text)
        } else if let text {
            text.lineLimit(oneLine ? 1 : 2).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
        } else {
            InspectorPlaceholder(text: placeholder)
        }
    }

    /// A yes or no is the system's checkbox; a value that is not set reads as unchecked, and Clear in the menu unsets it.
    private var checkbox: some View {
        Toggle(isOn: Binding { InspectorFields.isYes(value) } set: { input.rejected = !onChange(.bool($0)) }) {
            Text(LocalizedStringKey(definition.displayLabel))
        }
        .labelsHidden()
        .toggleStyle(.checkbox)
        .disabled(!isEditable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(LocalizedStringKey(definition.displayLabel))
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
            Button("Edit") { beginTextEdit() }.accessibilityIdentifier("ItemPropertyEdit.\(definition.key)")
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
            // A picked date is never held back as input, so only the other rows have anything kept.
            Group {
                if definition.kind.isDate {
                    Text("The date couldn’t be saved.")
                } else if definition.kind == .number, let requirement = definition.numberRule.requirement,
                          PropertyNumber.parse(input.text, rule: definition.numberRule) == nil {
                    Text(requirement)
                } else {
                    Text("The value could not be saved. Your input has been kept.")
                }
            }
            .interfaceFont(.caption)
            .foregroundStyle(.red)
            if !definition.kind.isDate {
                Button("Discard Changes") { input.discard(toMatch: currentText); editing = false }
                    .interfaceFont(.caption)
            }
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
        switch definition.kind {
        case .date: choosingDate = true
        case .text, .number: isFocused = true
        default: break
        }
    }

    /// The options of a choice, in the system's pop-up menu: it takes typing to jump to an option, and a long option
    /// is cut inside the value column.
    private func choiceMenu() -> some View {
        let current = value?.string
        let text = current.map { Text(verbatim: ItemTypeInfo.Field.label(ofOption: $0)) }
        return Menu {
            Picker(LocalizedStringKey(definition.displayLabel), selection: Binding {
                current ?? ""
            } set: { selected in
                input.rejected = !onChange(selected.isEmpty ? nil : .string(selected))
            }) {
                Text("Not Set").tag("")
                ForEach(definition.options(including: current), id: \.self) {
                    Text(verbatim: ItemTypeInfo.Field.label(ofOption: $0)).tag($0)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            choiceLabel(text, placeholder: "Choose")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(LocalizedStringKey(definition.displayLabel))
        .accessibilityValue(text ?? Text("Not Set"))
        .accessibilityIdentifier("ItemProperty.\(definition.key)")
    }

    /// The value reads as a person writes a date, and changes only through the calendar, so what is stored is
    /// always one of the forms Marfa takes.
    private var dateButton: some View {
        Button { choosingDate = true } label: {
            choiceLabel(dateText.map { Text(verbatim: $0) }, placeholder: "None", oneLine: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $choosingDate, arrowEdge: .bottom) { datePicker }
        .accessibilityLabel(LocalizedStringKey(definition.displayLabel))
        .accessibilityValue(dateText.map { Text(verbatim: $0) } ?? Text("Not Set"))
        .accessibilityHint("Opens a calendar")
        .accessibilityIdentifier("ItemProperty.\(definition.key)")
    }

    /// Where the value links to, if it is a web or mail address.
    private var link: URL? { InspectorFields.link(of: definition, value: value) }

    /// A date as the person reads it; a value that is not one keeps its text, and the row warns about it.
    private var dateText: String? {
        guard let text = value?.string, !text.isEmpty else { return nil }
        return ItemDate.parse(text)?.text() ?? text
    }

    private var storedDate: ItemDate? { value?.string.flatMap { ItemDate.parse($0) } }

    /// A `datetime` field may hold a day or a moment, so it shows a time only once the value has one or the person
    /// asks for one; a `date` field never does.
    private var allowsTime: Bool {
        if case .date(let includesTime) = definition.kind { includesTime } else { false }
    }

    private var datePicker: some View {
        let hasTime = allowsTime && (storedDate?.hasTime ?? false)
        return VStack(alignment: .leading, spacing: 10) {
            DatePicker("Choose Date", selection: Binding {
                storedDate?.date ?? Date()
            } set: { setDate($0, includingTime: hasTime) }, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
            .datePickerStyle(.graphical)
            .labelsHidden()
            .accessibilityIdentifier("ItemPropertyDate.\(definition.key)")
            if allowsTime {
                Toggle("Time", isOn: Binding { hasTime } set: { include in
                    setDate(storedDate?.date ?? Date(), includingTime: include)
                })
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityIdentifier("ItemPropertyTime.\(definition.key)")
            }
            HStack {
                // The picker already shows today for an empty date, and picking the day it shows may change nothing.
                Button("Today") { setDate(Date(), includingTime: hasTime) }
                    .accessibilityIdentifier("ItemPropertyToday.\(definition.key)")
                Spacer()
                Button("Clear") { clearDate() }
                    .disabled(value == nil)
                    .accessibilityIdentifier("ItemPropertyClear.\(definition.key)")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .fixedSize()
    }

    private func setDate(_ selected: Date, includingTime: Bool) {
        let text = includingTime ? ItemDate.moment(selected) : ItemDate.day(selected)
        input.rejected = !onChange(.string(text))
        if !input.rejected { input.text = text; input.isDirty = false }
    }

    private func clearDate() {
        input.rejected = !onChange(nil)
        if !input.rejected { input.text = ""; input.isDirty = false; choosingDate = false }
    }

    /// The field that edits a value: the system's borderless text field, which reads as plain text at rest and shows
    /// its focus ring while it is in use. At rest a value of words is cut at three lines and a single word, as a
    /// link or an identifier is, at one; in use it grows.
    private var textField: some View {
        let isNumber = definition.kind == .number
        let text = input.isDirty ? input.text : currentText
        let token = InspectorText.isToken(text)
        return TextField(LocalizedStringKey(definition.displayLabel), text: Binding {
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
        case (.date, .string): valid = definition.kind.accepts(value)
        case (.other, _): valid = true
        case (.list, _): valid = definition.accepts(value)
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
            input.list.leave(shape, label: definition.displayLabel, value: value, isEditable: isEditable, write: onChange, to: library.notices)
            return
        }
        input.handOff(
            label: definition.displayLabel, as: definition.kind, rule: definition.numberRule, current: currentText,
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
