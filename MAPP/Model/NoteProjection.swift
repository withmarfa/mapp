import Foundation
import Yams

/// JSON-compatible values read from YAML, without assigning Marfa property semantics to header fields.
nonisolated indirect enum NoteFieldValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([NoteFieldValue])
    case object([String: NoteFieldValue])

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}

nonisolated struct NoteFrontMatterError: Error, Equatable, Sendable {
    let message: String
}

nonisolated enum NoteFrontMatter: Equatable, Sendable {
    case absent
    case parsed([String: NoteFieldValue])
    case invalid(NoteFrontMatterError)
}

/// A read-only view of a file. The original envelope remains the authority for saving and editing.
nonisolated struct NoteProjection: Identifiable, Equatable, Sendable {
    let id: UUID
    let file: NoteFile
    let frontMatter: NoteFrontMatter
    let title: String
    let declaredType: String?

    var body: String { file.body }

    var fields: [String: NoteFieldValue]? {
        guard case .parsed(let fields) = frontMatter else { return nil }
        return fields
    }

    init(note: Note) {
        self.init(id: note.id, file: note.file, fallbackTitle: note.title)
    }

    init(id: UUID, file: NoteFile, fallbackTitle: String) {
        self.id = id
        self.file = file
        frontMatter = Self.parse(file.frontMatter)
        let fields: [String: NoteFieldValue]
        if case .parsed(let parsed) = frontMatter { fields = parsed } else { fields = [:] }
        let headerTitle = fields["title"]?.string
        title = headerTitle.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? fallbackTitle
        declaredType = fields["type"]?.string
    }

    private static func parse(_ envelope: String) -> NoteFrontMatter {
        guard !envelope.isEmpty else { return .absent }
        var lines = envelope.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        lines.removeFirst()
        lines.removeLast()
        do {
            // Composition retains scalar spelling, unlike loading timestamps into Foundation dates.
            guard let node = try Yams.compose(yaml: lines.joined(separator: "\n")) else {
                return .parsed([:])
            }
            if case .scalar(let scalar) = node, node.tag.rawValue == Tag.Name.null.rawValue, scalar.string.isEmpty {
                return .parsed([:])
            }
            guard case .object(let fields) = try value(node) else {
                throw NoteFrontMatterError(message: "Front matter must be a mapping with string keys.")
            }
            return .parsed(fields)
        } catch let error as NoteFrontMatterError {
            return .invalid(error)
        } catch {
            return .invalid(.init(message: String(describing: error)))
        }
    }

    private static func value(_ node: Node) throws -> NoteFieldValue {
        switch node {
        case .mapping(let mapping):
            guard node.tag.rawValue == Tag.Name.map.rawValue else {
                throw NoteFrontMatterError(message: "Unsupported YAML mapping tag: \(node.tag.rawValue)")
            }
            var fields: [String: NoteFieldValue] = [:]
            for (keyNode, valueNode) in mapping {
                guard case .scalar(let key) = keyNode, keyNode.tag.rawValue == Tag.Name.str.rawValue else {
                    throw NoteFrontMatterError(message: "Front matter mappings require string keys.")
                }
                guard fields[key.string] == nil else {
                    throw NoteFrontMatterError(message: "Duplicate front matter key: \(key.string)")
                }
                fields[key.string] = try value(valueNode)
            }
            return .object(fields)
        case .sequence(let sequence):
            guard node.tag.rawValue == Tag.Name.seq.rawValue else {
                throw NoteFrontMatterError(message: "Unsupported YAML sequence tag: \(node.tag.rawValue)")
            }
            return .array(try sequence.map(value))
        case .scalar(let scalar):
            switch node.tag.rawValue {
            case Tag.Name.str.rawValue, Tag.Name.timestamp.rawValue:
                return .string(scalar.string)
            case Tag.Name.null.rawValue:
                return .null
            case Tag.Name.bool.rawValue:
                guard let boolean = Bool.construct(from: scalar) else {
                    throw NoteFrontMatterError(message: "Invalid YAML boolean: \(scalar.string)")
                }
                return .bool(boolean)
            case Tag.Name.int.rawValue:
                let integer = Int64.construct(from: scalar).map(String.init)
                    ?? UInt64.construct(from: scalar).map(String.init)
                guard let integer, let number = Decimal(string: integer, locale: Locale(identifier: "en_US_POSIX")) else {
                    throw NoteFrontMatterError(message: "YAML integer cannot be represented: \(scalar.string)")
                }
                return .number(number)
            case Tag.Name.float.rawValue:
                guard let number = Double.construct(from: scalar), number.isFinite else {
                    throw NoteFrontMatterError(message: "YAML number must be finite: \(scalar.string)")
                }
                let spelling = scalar.string.replacingOccurrences(of: "_", with: "")
                // Going through Double would hide rounding in sexagesimal values. Unsupported number
                // spellings stay in the original file and receive a diagnostic rather than an estimate.
                guard !spelling.contains(":") else {
                    throw NoteFrontMatterError(message: "YAML sexagesimal number cannot be projected exactly: \(scalar.string)")
                }
                let decimal = Decimal(string: spelling, locale: Locale(identifier: "en_US_POSIX"))
                guard let decimal, !decimal.isNaN else {
                    throw NoteFrontMatterError(message: "YAML number cannot be represented: \(scalar.string)")
                }
                // Decimal(string:) can succeed after discarding significant digits. Compare numeric
                // spellings so exponent forms and insignificant trailing zeros do not look like loss.
                guard let exact = decimalSpelling(spelling),
                      exact == decimalSpelling(NSDecimalNumber(decimal: decimal).stringValue) else {
                    throw NoteFrontMatterError(message: "YAML number cannot be represented exactly: \(scalar.string)")
                }
                return .number(decimal)
            default:
                throw NoteFrontMatterError(message: "Unsupported YAML scalar tag: \(node.tag.rawValue)")
            }
        case .alias:
            // Yams composition resolves aliases to their anchored nodes before returning the tree.
            throw NoteFrontMatterError(message: "Unresolved YAML alias.")
        }
    }

    private static func decimalSpelling(_ text: String) -> String? {
        var text = text.lowercased()
        let negative = text.hasPrefix("-")
        if text.hasPrefix("-") || text.hasPrefix("+") { text.removeFirst() }
        let parts = text.split(separator: "e", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard mantissa.count == 1 || mantissa.count == 2 else { return nil }
        var digits = mantissa.joined()
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        digits = String(digits.drop(while: { $0 == "0" }))
        if digits.isEmpty { return "0" }
        guard let exponent = parts.count == 2 ? Int(parts[1]) : 0 else { return nil }
        let fractionDigits = mantissa.count == 2 ? mantissa[1].count : 0
        let (baseExponent, subtractionOverflow) = exponent.subtractingReportingOverflow(fractionDigits)
        guard !subtractionOverflow else { return nil }
        let count = digits.count
        while digits.last == "0" { digits.removeLast() }
        let (normalizedExponent, additionOverflow) = baseExponent.addingReportingOverflow(count - digits.count)
        guard !additionOverflow else { return nil }
        return "\(negative ? "-" : "")\(digits)e\(normalizedExponent)"
    }
}
