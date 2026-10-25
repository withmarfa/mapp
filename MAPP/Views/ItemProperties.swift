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
    @State private var localDraft = ItemPropertyDraft()
    @State private var rowHovering = false
    @State private var choosingDate = false
    /// A field that recommends values is a menu of them; Other… swaps it for a text field for a value of the
    /// person's own, until the person is done typing it.
    @State private var typingOwnValue = false
    @FocusState private var dateButtonFocused: Bool
    private var input: ItemPropertyDraft { retainedDraft ?? localDraft }
    @FocusState private var isFocused: Bool

    var body: some View {
        InspectorRow(name: LocalizedStringKey(definition.displayLabel)) {
            VStack(alignment: .leading, spacing: 4) {
                if isEditable {
                    control
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
                    Text("The value could not be saved. Your input has been kept.")
                        .interfaceFont(.caption)
                        .foregroundStyle(.red)
                    Button("Discard Changes") {
                        input.isDirty = false
                        seed(value)
                    }
                    .interfaceFont(.caption)
                }
            }
        }
        .onHover { rowHovering = $0 }
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

    @ViewBuilder private var control: some View {
        switch definition.kind {
        case .choice:
            choiceMenu()
        case .boolean:
            let current: Bool? = if case .bool(let selected) = value { selected } else { nil }
            menu(current: current.map { Text($0 ? "Yes" : "No") }) {
                Picker(LocalizedStringKey(definition.displayLabel), selection: Binding {
                    current.map { $0 ? "true" : "false" } ?? ""
                } set: { selected in
                    input.rejected = !onChange(selected.isEmpty ? nil : .bool(selected == "true"))
                }) {
                    Text("Not Set").tag("")
                    Text("Yes").tag("true")
                    Text("No").tag("false")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        case .date:
            HStack(spacing: 4) {
                textField
                // Always there, so the keyboard and VoiceOver reach it; it is drawn only where a pointer or the
                // keyboard is, so the row at rest shows nothing but its value.
                Button { choosingDate = true } label: { Image(systemName: "calendar") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .focused($dateButtonFocused)
                    .opacity(rowHovering || isFocused || dateButtonFocused || choosingDate ? 1 : 0)
                    .accessibilityLabel("Choose Date")
                    .accessibilityIdentifier("ItemPropertyDate.\(definition.key)")
                    .popover(isPresented: $choosingDate, arrowEdge: .bottom) { datePicker }
            }
            .accessibilityAction(named: "Choose Date") { choosingDate = true }
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
        if definition.kind == .boolean, case .bool(let flag) = value { return Text(flag ? "Yes" : "No") }
        if definition.isPicked, let option = value.string {
            return Text(LocalizedStringKey(ItemTypeInfo.Field.label(ofOption: option)))
        }
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

    /// A choice as plain text that opens a menu: no chevron and no fill until hovered. The button style with a plain
    /// label, unlike the borderless one, adds no inset of its own, so the text starts where a text value does.
    private func menu<Content: View>(current: Text?, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            Group {
                if let current { current } else { InspectorPlaceholder(text: "Choose") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .inspectorValue()
        .accessibilityLabel(LocalizedStringKey(definition.displayLabel))
        .accessibilityValue(current == nil ? Text("Not Set") : current!)
        .accessibilityIdentifier("ItemProperty.\(definition.key)")
    }

    private var datePicker: some View {
        let dateOnly = isDateOnly
        return VStack(spacing: 8) {
            DatePicker("Choose Date", selection: Binding {
                Self.date(value?.string) ?? Date()
            } set: { setDate($0) }, displayedComponents: dateOnly ? [.date] : [.date, .hourAndMinute])
            .datePickerStyle(.graphical)
            .labelsHidden()
            // The picker already shows today for an empty date, and picking the day it shows may change nothing.
            Button("Today") { setDate(Date()) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("ItemPropertyToday.\(definition.key)")
        }
        .padding(12)
    }

    /// A date of ten characters is a day, as an empty one is until the person picks a time.
    private var isDateOnly: Bool { (value?.string ?? "").isEmpty || value?.string?.count == 10 }

    private func setDate(_ selected: Date) {
        let text = isDateOnly
            ? selected.formatted(.iso8601.year().month().day().dateSeparator(.dash))
            : selected.ISO8601Format()
        input.rejected = !onChange(.string(text))
        if !input.rejected { input.text = text; input.isDirty = false }
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
        case (.date, .string(let text)): valid = text.isEmpty || Self.date(text) != nil
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

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = try? Date(value, strategy: .iso8601) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
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
            ItemPropertyRow(definition: .init(key: "occurred_at", label: "Decided", kind: .date, declaredBy: TypeID("aic.decision")),
                            value: .string("2026-10-02"), isEditable: true, onChange: { _ in true })
        }
        .padding(16)
    }
    .interfaceTextStyle()
    .frame(width: 300, height: 440)
}
#endif
