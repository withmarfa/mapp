import SwiftUI

/// Each row keeps unfinished input until it is committed; unrelated inspector updates do not replace it.
struct ItemPropertyRow: View {
    let definition: ItemPropertyDefinition
    let value: NoteFieldValue?
    let isEditable: Bool
    let onChange: (NoteFieldValue?) -> Bool
    @State private var draft = ""
    @State private var isDirty = false
    @State private var rejected = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            control
                .disabled(!isEditable)
            if let invalidValue {
                Text(invalidValue).font(.caption).foregroundStyle(.orange)
            }
            if rejected {
                Text("The value could not be saved. Your input has been kept.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { seed() }
        .onChange(of: value) { if !isDirty { seed() } }
        .onChange(of: isFocused) { if !isFocused { commit() } }
        .onDisappear { commit() }
    }

    @ViewBuilder private var control: some View {
        switch definition.kind {
        case .choice(let choices):
            Picker(LocalizedStringKey(definition.label), selection: Binding {
                value?.string ?? ""
            } set: { selected in
                rejected = !onChange(selected.isEmpty ? nil : .string(selected))
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
                rejected = !onChange(selected.isEmpty ? nil : .bool(selected == "true"))
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
                        rejected = !onChange(.string(text))
                        if !rejected { draft = text; isDirty = false }
                    }, displayedComponents: value?.string?.count == 10 ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden()
                } else if value == nil || value?.string == "" {
                    Button("Set Date") {
                        let text = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
                        rejected = !onChange(.string(text))
                    }
                }
            }
        case .text, .number:
            textField
        }
    }

    private var textField: some View {
        TextField(LocalizedStringKey(definition.label), text: Binding { draft } set: {
            draft = $0
            isDirty = true
            rejected = false
        }, axis: definition.key == "description" ? .vertical : .horizontal)
        .lineLimit(definition.key == "description" ? 2...5 : 1...1)
        .focused($isFocused)
        .onSubmit { commit() }
        .accessibilityIdentifier("ItemProperty.\(definition.key)")
    }

    private var invalidValue: String? {
        guard let value else { return nil }
        let valid: Bool
        switch (definition.kind, value) {
        case (.text, .string), (.boolean, .bool), (.number, .number): valid = true
        case (.choice(let choices), .string(let text)): valid = choices.contains(text)
        case (.date, .string(let text)): valid = text.isEmpty || Self.date(text) != nil
        default: valid = false
        }
        return valid ? nil : String(localized: "Unrecognized value: \(ItemValueText.string(value)). It is preserved until you replace it.")
    }

    private func seed() {
        draft = value.map(ItemValueText.string) ?? ""
        rejected = false
    }

    private func commit() {
        guard isDirty, isEditable else { return }
        let value: NoteFieldValue?
        if draft.isEmpty {
            value = nil
        } else if case .number = definition.kind {
            let scanner = Scanner(string: draft)
            scanner.locale = Locale(identifier: "en_US_POSIX")
            var number = Decimal()
            guard scanner.scanDecimal(&number), scanner.isAtEnd, !number.isNaN else {
                rejected = true
                return
            }
            value = .number(number)
        } else {
            value = .string(draft)
        }
        rejected = !onChange(value)
        if !rejected { isDirty = false }
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
    static func string(_ value: NoteFieldValue) -> String {
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
    Form {
        ForEach(WorkbenchSchema.taskProperties) { definition in
            ItemPropertyRow(definition: definition, value: definition.key == "status" ? .string("in_progress") : nil,
                            isEditable: true, onChange: { _ in true })
        }
        ItemPropertyRow(definition: .init(key: "occurred_at", label: "Decided", kind: .date),
                        value: .string("2026-10-02"), isEditable: true, onChange: { _ in true })
    }
    .formStyle(.grouped)
    .frame(width: 320, height: 440)
}
