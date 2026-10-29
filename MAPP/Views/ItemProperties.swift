import SwiftUI

/// One property of an item as a row of the inspector. Its value reads as plain text, and a click turns it into
/// what edits it: a field, a menu or a calendar. Each row keeps unfinished input until it is committed; unrelated
/// inspector updates do not replace it, and a change made elsewhere meanwhile is never written over silently.
struct ItemPropertyRow: View {
    let definition: ItemTypeInfo.Field
    let value: PropertyValue?
    let isEditable: Bool
    let onChange: (PropertyValue?) -> Bool
    var retainedDraft: ItemPropertyDraft? = nil
    /// A row the person has just added opens ready to edit: a text field takes the keyboard and a date shows its
    /// picker. A menu cannot be opened from code, so it reads "Choose" instead.
    var startsEditing = false
    /// The type's status field: its value has the status's ring.
    var isStatus = false
    /// Whether the page shows this property too, and what changes it; nil offers no choice.
    var shownOnPage = true
    var onShowOnPage: ((Bool) -> Void)?
    @Environment(\.interfaceTextSize) private var textSize
    @Environment(\.openURL) private var openURL
    @Environment(\.library) private var library
    @State private var localDraft = ItemPropertyDraft()
    @State private var choosingDate = false
    @State private var choosingOption = false
    /// Whether a text value is being edited, as opposed to read.
    @State private var editing = false
    /// A field that recommends values is a menu of them; Other… swaps it for a text field for a value of the
    /// person's own, until the person is done typing it.
    @State private var typingOwnValue = false
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
                if input.rejected { rejectedNotice }
            }
        }
        .contextMenu { menu }
        .onAppear { if !input.isDirty { seed(value) } }
        .task { if startsEditing { await beginEditing() } }
        // The action may run on an earlier copy of this view, so it takes the value from the change itself.
        .onChange(of: value) { _, value in if !input.isDirty { seed(value) } }
        .onChange(of: isFocused) {
            guard !isFocused else { return }
            commit()
            typingOwnValue = false
            if !input.isDirty { editing = false }
        }
        .onDisappear(perform: leave)
    }

    // MARK: Value

    @ViewBuilder private var core: some View {
        if definition.kind == .boolean {
            checkbox
        } else if isEditable && (editing || input.isDirty || typingOwnValue) {
            textField
        } else if isEditable {
            switch definition.kind {
            case .choice: choiceValue()
            case .date: dateButton
            case .text where definition.isPicked: choiceValue(allowsOther: true)
            case .text, .number: restingText(opens: link == nil ? .edit : .link)
            case .other: plain
            case .boolean: EmptyView()
            }
        } else if link != nil {
            restingText(opens: .link)
        } else {
            plain
        }
    }

    private enum Click { case edit, link }

    /// The value as plain text. A link opens on a click, in the accent color; anything else is edited by one. The
    /// keyboard reaches either, and Return or Space edits a value that can be edited, a link included.
    @ViewBuilder private func restingText(opens click: Click) -> some View {
        switch click {
        case .link:
            if let link {
                let hint: LocalizedStringKey = link.scheme == "mailto" ? "Writes to this address" : "Opens this address"
                InspectorText(text: shownText, style: AnyShapeStyle(Color.accentColor))
                    .inspectorActivates(keyboard: isEditable ? { beginTextEdit() } : nil) { openURL(link) }
                    .pointerStyle(.link)
                    .accessibilityLabel(LocalizedStringKey(definition.displayLabel))
                    .accessibilityValue(shownText)
                    .accessibilityHint(hint)
                    .accessibilityIdentifier("ItemProperty.\(definition.key)")
            }
        case .edit:
            Group {
                if shownText.isEmpty { InspectorPlaceholder(text: "None") } else { InspectorText(text: shownText) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .inspectorActivates { beginTextEdit() }
            .pointerStyle(.horizontalText)
            .accessibilityLabel(LocalizedStringKey(definition.displayLabel))
            .accessibilityValue(shownText.isEmpty ? String(localized: "Not Set") : shownText)
            .accessibilityHint("Edits this value")
            .accessibilityIdentifier("ItemProperty.\(definition.key)")
        }
    }

    /// A value nothing here changes, read as a Details row is.
    @ViewBuilder private var plain: some View {
        if definition.kind.isDate, let dateText {
            InspectorText(text: dateText, keepsOneLine: true).accessibilityIdentifier("ItemProperty.\(definition.key)")
        } else if isStatus, let text = value?.string {
            statusLabel(Text(LocalizedStringKey(ItemTypeInfo.Field.label(ofOption: text))))
                .accessibilityIdentifier("ItemProperty.\(definition.key)")
        } else if case .choice = definition.kind, let text = value?.string {
            InspectorText(text: ItemTypeInfo.Field.label(ofOption: text)).accessibilityIdentifier("ItemProperty.\(definition.key)")
        } else if !shownText.isEmpty {
            InspectorText(text: shownText).accessibilityIdentifier("ItemProperty.\(definition.key)")
        }
    }

    private var currentText: String { value.map(ItemValueText.string) ?? "" }

    /// What the row reads at rest: the draft while there is one, else the stored value.
    private var shownText: String {
        if definition.kind.isDate, let dateText { return dateText }
        return input.isDirty ? input.text : currentText
    }

    private var statusMark: PageHeader.Mark { .init(status: value?.string) }

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
        let isYes = InspectorFields.yesNo(value) == .yes
        let write = { (selected: Bool) in input.rejected = !onChange(.bool(selected)) }
        return Toggle(isOn: Binding { isYes } set: { write($0) }) {
            Text(LocalizedStringKey(definition.displayLabel))
        }
        .labelsHidden()
        .toggleStyle(.checkbox)
        .disabled(!isEditable)
        // A checkbox is skipped by Tab unless full keyboard access is on.
        .focusable(isEditable)
        .onKeyPress(keys: [.return, .space], phases: .down) { _ in
            write(!isYes)
            return .handled
        }
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

    private var rejectedNotice: some View {
        VStack(alignment: .leading, spacing: 2) {
            // A picked date is never held back as input, so only the other rows have anything kept.
            Group {
                if definition.kind.isDate {
                    Text("The date couldn’t be saved.")
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
        // The field is in the tree one turn after the row asks for it.
        await Task.yield()
        isFocused = true
    }

    private func beginEditing() async {
        await Task.yield()
        switch definition.kind {
        case .date: choosingDate = true
        case .text where !definition.isPicked: editing = true; await focus()
        case .number: editing = true; await focus()
        default: break
        }
    }

    /// The options of a choice, opened from the value by a click, Return or Space.
    private func choiceValue(allowsOther: Bool = false) -> some View {
        let current = value?.string
        let text = current.map { Text(LocalizedStringKey(ItemTypeInfo.Field.label(ofOption: $0))) }
        return choiceLabel(text, placeholder: "Choose")
            .frame(maxWidth: .infinity, alignment: .leading)
            .inspectorActivates { choosingOption = true }
            .popover(isPresented: $choosingOption, arrowEdge: .bottom) {
                InspectorChoiceList(
                    entries: [.init(id: "", label: "Not Set")]
                        + definition.options(including: current).map { .init(id: $0, label: LocalizedStringKey(ItemTypeInfo.Field.label(ofOption: $0))) },
                    selected: current ?? "", allowsOther: allowsOther,
                    onPick: { selected in
                        choosingOption = false
                        input.rejected = !onChange(selected.isEmpty ? nil : .string(selected))
                    },
                    onOther: {
                        choosingOption = false
                        typingOwnValue = true
                        Task { await focus() }
                    })
            }
            .accessibilityLabel(LocalizedStringKey(definition.displayLabel))
            .accessibilityValue(text ?? Text("Not Set"))
            .accessibilityHint("Opens the choices")
            .accessibilityIdentifier("ItemProperty.\(definition.key)")
    }

    /// The value reads as a person writes a date, and changes only through the calendar, so what is stored is
    /// always one of the forms Marfa takes.
    private var dateButton: some View {
        choiceLabel(dateText.map { Text(verbatim: $0) }, placeholder: "None", oneLine: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .inspectorActivates { choosingDate = true }
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

    /// The field that edits a value. It is boxed only while it is in use, so a value at rest is never a control.
    private var textField: some View {
        TextField(LocalizedStringKey(definition.displayLabel), text: Binding { input.text } set: {
            input.text = $0
            input.isDirty = true
            input.rejected = false
        }, prompt: Text(""), axis: definition.kind == .number ? .horizontal : .vertical)
        .labelsHidden()
        .textFieldStyle(.plain)
        .focusEffectDisabled()
        .multilineTextAlignment(.leading)
        .lineLimit(definition.kind == .number ? 1...1 : 1...12)
        .focused($isFocused)
        .onSubmit { commit(); typingOwnValue = false }
        .onExitCommand { input.discard(toMatch: currentText); editing = false; typingOwnValue = false; isFocused = false }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator) }
                .padding(.horizontal, -5)
                .padding(.vertical, -2)
        }
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
        default: valid = false
        }
        return valid ? nil : String(localized: "Unrecognized value: \(ItemValueText.string(value)). It is preserved until you replace it.")
    }

    private func seed(_ value: PropertyValue?) {
        input.text = value.map(ItemValueText.string) ?? ""
        input.base = input.text
        input.rejected = false
    }

    /// Leaves nothing the person typed behind: text that cannot be written goes back to them through `Notices`, which
    /// puts it on the clipboard, and the draft is dropped so it is told once.
    private func leave() {
        guard let loss = input.loss(as: definition.kind, current: currentText, isEditable: isEditable) else {
            commit()
            return
        }
        let reason = switch loss {
        case .conflict: String(localized: "The value changed while you were editing it.")
        case .notANumber: String(localized: "The value isn’t a number.")
        case .notEditable: String(localized: "The item can no longer be edited.")
        }
        library?.notices.notKept(
            String(localized: "Property Not Saved"), text: "\(definition.displayLabel): \(input.text)", reason: reason)
        input.discard(toMatch: currentText)
        editing = false
        typingOwnValue = false
    }

    private func commit(overwriting: Bool = false) {
        guard isEditable else { return }
        switch input.commit(as: definition.kind, current: currentText, overwriting: overwriting) {
        case .unchanged, .conflict:
            break
        case .alreadyCurrent:
            // The edit was undone by hand, or the item already holds it; the item's own text stands.
            input.discard(toMatch: currentText)
        case .invalid:
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
}

#if DEBUG
#Preview("Property Controls") {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SampleLibrary.catalogue.itemTypes[TypeID("core.task")]?.fields ?? []) { definition in
                ItemPropertyRow(definition: definition, value: definition.key == "status" ? .string("in_progress") : nil,
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
