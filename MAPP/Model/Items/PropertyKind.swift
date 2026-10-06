import Foundation

nonisolated extension ItemTypeInfo.Field.Kind {
    /// Whether a value of this shape can be written to the field. A date is a day or a full timestamp.
    func accepts(_ value: PropertyValue) -> Bool {
        switch (self, value) {
        case (.text, .string): true
        case (.choice(let choices), .string(let string)): choices.contains(string)
        case (.date, .string(let string)):
            string.isEmpty || ISO8601DateFormatter().date(from: string) != nil
                || DateFormatter.itemDay.date(from: string) != nil
        case (.boolean, .bool), (.number, .number): true
        default: false
        }
    }
}

nonisolated extension DateFormatter {
    /// A date with no time, as the workbench's fields write one.
    static var itemDay: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}
