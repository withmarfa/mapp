import SwiftUI

/// One property of an item as a row of the inspector's property sheet. Each row keeps unfinished input until it
/// is committed; unrelated inspector updates do not replace it.
struct ItemPropertyRow: View {
    let definition: ItemTypeInfo.Field
    let value: PropertyValue?
    let isEditable: Bool
    let onChange: (PropertyValue?) -> Bool
    var retainedDraft: ItemPropertyDraft? = nil
    /// A row the person has just added opens ready to edit: a text field takes the keyboard and a date shows its
    /// picker. A menu cannot be opened from code, so it reads "Choose" instead.
    var startsEditing = false
    /// The type's status field: its value is a chip with the status's ring.
    var isStatus = false
    /// Whether the page shows this property too, and what changes it; nil offers no choice.
    var shownOnPage = true
    var onShowOnPage: ((Bool) -> Void)?
    @Environment(\.interfaceTextSize) private var textSize
    @State private var localDraft = ItemPropertyDraft()
    @State private var choosingDate = false
    /// A field that recommends values is a menu of them; Other… swaps it for a text field for a value of the
    /// person's own, until the person is done typing it.
    @State private var typingOwnValue = false
    @FocusState private var dateButtonFocused: Bool
    private var input: ItemPropertyDraft { retainedDraft ?? localDraft }
    @FocusState private var isFocused: Bool

    var body: some View {
        InspectorRow(fieldLabel: definition.displayLabel, fit: fit) {
            VStack(alignment: .leading, spacing: 4) {
                if isEditable {
                    control
                } else if definition.kind == .boolean {
                    checkbox
                } else if shapesAsChip, let chipText {
                    // A value that cannot be changed is still a chip, but not a control.
                    HStack(spacing: 0) {
                        chipLabel(chipText)
                            .inspectorChip()
                            .textSelection(.enabled)
                            .accessibilityIdentifier("ItemProperty.\(definition.key)")
                        Spacer(minLength: 0)
                    }
                } else if let readOnlyText {
                    // A value that cannot be changed reads as a Details row does, not as a dimmed control.
                    readOnlyText
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("ItemProperty.\(definition.key)")
                }
                if let invalidValue {
                    Text(invalidValue).interfaceFont(.caption).foregroundStyle(.orange)
                }
                if input.rejected {
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
                        Button("Discard Changes") {
                            input.isDirty = false
                            seed(value)
                        }
                        .interfaceFont(.caption)
                    }
                }
            }
        }
        .showOnPageMenu(isShown: shownOnPage, onChange: onShowOnPage)
        .onAppear { if !input.isDirty { seed(value) } }
        .task { if startsEditing { await beginEditing() } }
        // The action may run on an earlier copy of this view, so it takes the value from the change itself.
        .onChange(of: value) { _, value in if !input.isDirty { seed(value) } }
        .onChange(of: isFocused) { if !isFocused { commit(); typingOwnValue = false } }
        .onDisappear { commit() }
    }

    private func beginEditing() async {
        // The control is in the tree one turn after the row appears.
        await Task.yield()
        switch definition.kind {
        case .date: choosingDate = true
        case .text where !definition.isPicked: isFocused = true
        case .number: isFocused = true
        default: break
        }
    }

    /// A choice, a status and a date have a shape of their own, drawn as a chip.
    private var shapesAsChip: Bool {
        switch definition.kind {
        case .choice, .date: true
        case .text: definition.isPicked
        default: false
        }
    }

    /// The text of the value's chip, or nil where it has none.
    private var chipText: Text? {
        if definition.kind.isDate { return dateText.map { Text(verbatim: $0) } }
        return value?.string.map { Text(LocalizedStringKey(ItemTypeInfo.Field.label(ofOption: $0))) }
    }

    private var statusMark: PageHeader.Mark { .init(status: value?.string) }

    private var chipPlaceholder: LocalizedStringKey { definition.kind.isDate ? "None" : "Choose" }

    /// The inside of a chip: the status's ring where the property is the status, then the value or what stands for
    /// none.
    private func chipLabel(_ text: Text?) -> some View {
        HStack(spacing: 6) {
            if isStatus { StatusMark(mark: statusMark, size: 10 * InterfaceStyle.scale(for: textSize)) }
            if let text { text } else { InspectorPlaceholder(text: chipPlaceholder) }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// What the row measures to choose between a value beside the name and one under it.
    private var fit: InspectorFit? {
        if definition.kind == .boolean { return nil }
        let chip = InspectorMetrics.chipPadding + (isStatus ? 16 : 0)
        if shapesAsChip {
            let text = definition.kind.isDate
                ? dateText ?? String(localized: "None")
                : value?.string.map(ItemTypeInfo.Field.label(ofOption:)) ?? String(localized: "Choose")
            return InspectorFit(text: text, extra: chip)
        }
        guard let value else { return nil }
        let text = ItemValueText.string(value)
        // A value of several lines never sits beside its name.
        return InspectorFit(text: text, extra: text.contains(where: \.isNewline) ? 10_000 : 0)
    }

    private var checkbox: some View {
        let current: Bool = if case .bool(let selected) = value { selected } else { false }
        return Toggle(isOn: Binding { current } set: { selected in
            input.rejected = !onChange(.bool(selected))
        }) {
            Text(LocalizedStringKey(definition.displayLabel))
        }
        .labelsHidden()
        .toggleStyle(.checkbox)
        .disabled(!isEditable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(LocalizedStringKey(definition.displayLabel))
        .accessibilityIdentifier("ItemProperty.\(definition.key)")
    }

    @ViewBuilder private var control: some View {
        switch definition.kind {
        case .choice:
            choiceMenu()
        case .boolean:
            checkbox
        case .date:
            // The value reads as a person writes a date, and changes only through the calendar, so what is stored
            // is always one of the forms Marfa takes.
            HStack(spacing: 0) {
                Button { choosingDate = true } label: { chipLabel(chipText) }
                    .buttonStyle(InspectorChipStyle())
                    .foregroundStyle(.primary)
                    .focused($dateButtonFocused)
                    .popover(isPresented: $choosingDate, arrowEdge: .bottom) { datePicker }
                    .accessibilityLabel(LocalizedStringKey(definition.displayLabel))
                    .accessibilityValue(dateText.map { Text(verbatim: $0) } ?? Text("Not Set"))
                    .accessibilityHint("Opens a calendar")
                    .accessibilityIdentifier("ItemProperty.\(definition.key)")
                Spacer(minLength: 0)
            }
        // Marfa only recommends these values, so any other text is as valid: the menu offers them, and Other… types one.
        case .text where definition.isPicked:
            if typingOwnValue {
                textField
                    .task { isFocused = true }
            } else {
                choiceMenu(allowsOther: true)
            }
        case .text, .number:
            textField
        // A list or an object is shown as written, since a text field would replace it with a string.
        case .other:
            if let value {
                Text(ItemValueText.string(value))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The value as the control would show it: a choice by its label, a Boolean as Yes or No, anything else as written.
    private var readOnlyText: Text? {
        guard let value else { return nil }
        return Text(ItemValueText.string(value))
    }

    private func choiceMenu(allowsOther: Bool = false) -> some View {
        let current = value?.string
        return menu(current: current.map { Text(LocalizedStringKey(ItemTypeInfo.Field.label(ofOption: $0))) }) {
            Picker(LocalizedStringKey(definition.displayLabel), selection: Binding {
                current ?? ""
            } set: { selected in
                input.rejected = !onChange(selected.isEmpty ? nil : .string(selected))
            }) {
                Text("Not Set").tag("")
                ForEach(definition.options(including: current), id: \.self) {
                    Text(LocalizedStringKey(ItemTypeInfo.Field.label(ofOption: $0))).tag($0)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if allowsOther {
                Divider()
                Button("Other…") { typingOwnValue = true }
                    .accessibilityIdentifier("ItemPropertyOther.\(definition.key)")
            }
        }
    }

    /// A choice as a chip that opens a menu.
    private func menu<Content: View>(current: Text?, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Menu {
                content()
            } label: {
                chipLabel(current)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(InspectorChipStyle())
            .foregroundStyle(.primary)
            .accessibilityLabel(LocalizedStringKey(definition.displayLabel))
            .accessibilityValue(current == nil ? Text("Not Set") : current!)
            .accessibilityIdentifier("ItemProperty.\(definition.key)")
            Spacer(minLength: 0)
        }
    }

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
        .frame(maxWidth: .infinity, alignment: .leading)
        // Drawn here and not as the field's prompt, whose colour differs from a menu's placeholder.
        .overlay(alignment: .topLeading) {
            if input.text.isEmpty && !isFocused { InspectorPlaceholder(text: "None").allowsHitTesting(false).accessibilityHidden(true) }
        }
        .inspectorValue(isFocused: isFocused)
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
        input.rejected = false
    }

    private func commit() {
        guard input.isDirty, isEditable else { return }
        let value: PropertyValue?
        if input.text.isEmpty {
            value = nil
        } else if case .number = definition.kind {
            let scanner = Scanner(string: input.text)
            scanner.locale = Locale(identifier: "en_US_POSIX")
            guard let number = scanner.scanDecimal(), scanner.isAtEnd, !number.isNaN else {
                input.rejected = true
                return
            }
            value = .number(number)
        } else {
            value = .string(input.text)
        }
        input.rejected = !onChange(value)
        if !input.rejected { input.isDirty = false }
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
