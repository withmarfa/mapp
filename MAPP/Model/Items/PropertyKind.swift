import Foundation

nonisolated extension ItemTypeInfo.Field.Kind {
    /// Whether a value of this shape can be written to the field. A `date` is a day; a `datetime` is a day or a
    /// moment (`ItemDate`).
    func accepts(_ value: PropertyValue) -> Bool {
        switch (self, value) {
        case (.text, .string): true
        case (.choice(let choices), .string(let string)): choices.contains(string)
        case (.date(let includesTime), .string(let string)):
            string.isEmpty || ItemDate.parse(string).map { includesTime || !$0.hasTime } == true
        case (.boolean, .bool), (.number, .number): true
        default: false
        }
    }

    var isDate: Bool {
        if case .date = self { true } else { false }
    }
}
