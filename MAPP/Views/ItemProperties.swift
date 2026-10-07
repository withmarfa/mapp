import SwiftUI

/// Each row keeps unfinished input until it is committed; unrelated inspector updates do not replace it.
struct ItemPropertyRow: View {
    let definition: ItemTypeInfo.Field
    let value: PropertyValue?
    let isEditable: Bool
    let onChange: (PropertyValue?) -> Bool
    var retainedDraft: ItemPropertyDraft? = nil
    @State private var localDraft = ItemPropertyDraft()
    private var input: ItemPropertyDraft { retainedDraft ?? localDraft }
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            control
                .disabled(!isEditable)
            if let invalidValue {
                Text(invalidValue).interfaceFont(.caption).foregroundStyle(.orange)
            }
            if input.rejected {
                Text("The value could not be saved. Your input has been kept.")
                    .interfaceFont(.caption)
                    .foregroundStyle(.red)
                Button("Discard Changes") {
                    input.isDirty = false
                    seed()
                }
                .interfaceFont(.caption)
            }
        }
        .onAppear { if !input.isDirty { seed() } }
        .onChange(of: value) { if !input.isDirty { seed() } }
        .onChange(of: isFocused) { if !isFocused { commit() } }
        .onDisappear { commit() }
    }

    @ViewBuilder private var control: some View {
        switch definition.kind {
        case .choice(let choices):
            Picker(LocalizedStringKey(definition.label), selection: Binding {
                value?.string ?? ""
            } set: { selected in
                input.rejected = !onChange(selected.isEmpty ? nil : .string(selected))
            }) {
                Text("Not Set").tag("")
                if let current = value?.string, !choices.contains(current) {
                    Text(current).tag(current)
                }
                ForEach(choices, id: \.self) { Text(LocalizedStringKey(Self.choiceLabel($0))).tag($0) }
            }
            .accessibilityIdentifier("ItemProperty.\(definition.key)")
        case .boolean:
            Picker(LocalizedStringKey(definition.label), selection: Binding {
                if case .bool(let selected) = value { selected ? "true" : "false" } else { "" }
            } set: { selected in
                input.rejected = !onChange(selected.isEmpty ? nil : .bool(selected == "true"))
            }) {
                Text("Not Set").tag("")
                Text("Yes").tag("true")
                Text("No").tag("false")
            }
            .accessibilityIdentifier("ItemProperty.\(definition.key)")
        case .date:
            VStack(alignment: .leading, spacing: 6) {
                textField
                if let date = Self.date(value?.string) {
                    DatePicker("Choose Date", selection: Binding {
                        date
                    } set: { selected in
                        let dateOnly = value?.string?.count == 10
                        let text = dateOnly
                            ? selected.formatted(.iso8601.year().month().day().dateSeparator(.dash))
                            : selected.ISO8601Format()
                        input.rejected = !onChange(.string(text))
                        if !input.rejected { input.text = text; input.isDirty = false }
                    }, displayedComponents: value?.string?.count == 10 ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden()
                } else if value == nil || value?.string == "" {
                    Button("Set Date") {
                        let text = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
                        input.rejected = !onChange(.string(text))
                    }
                }
            }
        case .text, .number:
            textField
        // A list or an object is shown as written, since a text field would replace it with a string.
        case .other:
            textField
                .disabled(true)
        }
    }

    private var textField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(definition.label))
                .interfaceFont(.subheadline).foregroundStyle(.secondary)
            TextField(LocalizedStringKey(definition.label), text: Binding { input.text } set: {
                input.text = $0
                input.isDirty = true
                input.rejected = false
            }, axis: definition.key == "description" ? .vertical : .horizontal)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(definition.key == "description" ? 2...5 : 1...1)
            .focused($isFocused)
            .onSubmit { commit() }
            .accessibilityIdentifier("ItemProperty.\(definition.key)")
        }
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

    private func seed() {
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
            var number = Decimal()
            guard scanner.scanDecimal(&number), scanner.isAtEnd, !number.isNaN else {
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

    static func choiceLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
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

#Preview("Property Controls") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WorkbenchSchema.catalogue.itemTypes[TypeID("aic.ticket.task")]?.fields ?? []) { definition in
                ItemPropertyRow(definition: definition, value: definition.key == "status" ? .string("in_progress") : nil,
                                isEditable: true, onChange: { _ in true })
            }
            ItemPropertyRow(definition: .init(key: "occurred_at", label: "Decided", kind: .date, declaredBy: TypeID("aic.decision")),
                            value: .string("2026-10-02"), isEditable: true, onChange: { _ in true })
        }
        .padding(16)
    }
    .frame(width: 320, height: 440)
}
