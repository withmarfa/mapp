import Foundation

/// A caller supplies the schema meaning of a header field, including reverse spellings.
nonisolated struct NoteConnectionRule: Equatable, Sendable {
    enum Direction: Equatable, Sendable { case forward, reverse }

    let field: String
    let name: String
    let reverseName: String?
    let direction: Direction
}

nonisolated enum NoteReferenceResolution: Equatable, Sendable {
    case resolved(UUID)
    case missing
    case ambiguous([UUID])
}

nonisolated struct NoteIndexedReference: Equatable, Sendable {
    enum Origin: Equatable, Sendable {
        case body
        case header(String)
    }

    let sourceID: UUID
    let origin: Origin
    let targetTitle: String
    let resolution: NoteReferenceResolution
}

/// Canonical direction, even when the file declares the connection using its reverse name.
nonisolated struct NoteConnectionEdge: Hashable, Sendable {
    let name: String
    let reverseName: String?
    let sourceID: UUID
    let targetID: UUID
}

nonisolated struct NoteConnectionIssue: Equatable, Sendable {
    let sourceID: UUID
    let field: String
    let value: NoteFieldValue
}

/// A snapshot rebuilt from files. Body references are lexical mentions, never semantic header edges.
nonisolated struct NoteConnectionIndex: Sendable {
    let references: [NoteIndexedReference]
    let edges: Set<NoteConnectionEdge>
    /// Configured fields containing malformed target references.
    let issues: [NoteConnectionIssue]

    init(records: [NoteProjection], rulesByType: [String: [NoteConnectionRule]]) {
        var names: [String: [UUID]] = [:]
        var declaredIDs: [UUID: [UUID]] = [:]
        for record in records {
            for name in Self.names(of: record) {
                let key = Self.nameKey(name)
                if !names[key, default: []].contains(record.id) {
                    names[key, default: []].append(record.id)
                }
            }
            // A file's declaration is a local lookup hint, not a verified Marfa identity.
            if let text = record.fields?["marfa_id"]?.string, let id = Self.itemID(text),
               !declaredIDs[id, default: []].contains(record.id) {
                declaredIDs[id, default: []].append(record.id)
            }
        }
        func matches(_ name: String) -> [UUID] {
            if let id = Self.itemID(name) { return declaredIDs[id, default: []] }
            return names[Self.nameKey(NoteName.trimmed(name)), default: []]
        }
        func resolve(_ title: String) -> NoteReferenceResolution {
            let name = Self.baseName(title)
            var found = matches(name)
            // Choosing the base when the whole spelling names another record would guess.
            if !found.isEmpty, title != name {
                for id in matches(title) where !found.contains(id) { found.append(id) }
            }
            switch found.count {
            case 0: return .missing
            case 1: return .resolved(found[0])
            default: return .ambiguous(found)
            }
        }

        var references: [NoteIndexedReference] = []
        var edges: Set<NoteConnectionEdge> = []
        var issues: [NoteConnectionIssue] = []
        for record in records {
            for title in Self.bodyTargets(record.body) {
                references.append(.init(sourceID: record.id, origin: .body, targetTitle: title, resolution: resolve(title)))
            }
            guard let fields = record.fields else { continue }
            let type = record.declaredType ?? "core.note"
            for rule in rulesByType[type, default: []] {
                guard let field = fields[rule.field] else { continue }
                let values: [NoteFieldValue]
                if case .array(let array) = field { values = array } else { values = [field] }
                for value in values {
                    guard let string = value.string, let title = Self.typedTarget(string) else {
                        issues.append(.init(sourceID: record.id, field: rule.field, value: value))
                        continue
                    }
                    let resolution = resolve(title)
                    references.append(.init(sourceID: record.id, origin: .header(rule.field), targetTitle: title, resolution: resolution))
                    guard case .resolved(let targetID) = resolution else { continue }
                    let forward = rule.direction == .forward
                    edges.insert(.init(name: rule.name, reverseName: rule.reverseName,
                                       sourceID: forward ? record.id : targetID,
                                       targetID: forward ? targetID : record.id))
                }
            }
        }
        self.references = references
        self.edges = edges
        self.issues = issues
    }

    private static func nameKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
            .precomposedStringWithCanonicalMapping
    }

    private static func names(of record: NoteProjection) -> [String] {
        let title = NoteName.trimmed(record.title)
        guard let path = record.filePath else { return [title] }
        let filename = (path as NSString).lastPathComponent
        // File names retain their whitespace; only titles and typed names are trimmed.
        return [title, path, (path as NSString).deletingPathExtension,
                filename, (filename as NSString).deletingPathExtension]
    }

    private static func itemID(_ text: String) -> UUID? {
        guard text.count == 36 else { return nil }
        return UUID(uuidString: text)
    }

    private static func baseName(_ title: String) -> String {
        // A combining mark can share a grapheme with the delimiter, but cannot hide it.
        let base = title.unicodeScalars.prefix { $0 != "|" && $0 != "#" }
        return NoteName.trimmed(String(String.UnicodeScalarView(base)))
    }

    private static func typedTarget(_ text: String) -> String? {
        let text = NoteName.trimmed(text)
        let scalars = text.unicodeScalars
        guard scalars.count > 4, scalars.prefix(2).elementsEqual("[[".unicodeScalars),
              scalars.suffix(2).elementsEqual("]]".unicodeScalars) else { return nil }
        let title = NoteName.trimmed(String(String.UnicodeScalarView(scalars.dropFirst(2).dropLast(2))))
        guard !title.isEmpty,
              !title.unicodeScalars.contains(where: { $0 == "[" || $0 == "]" || $0 == "\n" || $0 == "\r" }) else { return nil }
        guard !baseName(title).isEmpty else { return nil }
        return title
    }

    private static func bodyTargets(_ body: String) -> [String] {
        body.matches(of: /\[\[([^\[\]\r\n]+)\]\]/.matchingSemantics(.unicodeScalar)).compactMap { match in
            typedTarget(String(match.output.0))
        }
    }
}
