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
    /// Configured fields containing values other than exact title references.
    let issues: [NoteConnectionIssue]

    init(records: [NoteProjection], rulesByType: [String: [NoteConnectionRule]]) {
        let titles = Dictionary(grouping: records, by: { Self.titleKey($0.title) })
        func resolve(_ title: String) -> NoteReferenceResolution {
            let matches = titles[Self.titleKey(title), default: []].map(\.id)
            switch matches.count {
            case 0: return .missing
            case 1: return .resolved(matches[0])
            default: return .ambiguous(matches)
            }
        }

        var references: [NoteIndexedReference] = []
        var edges: Set<NoteConnectionEdge> = []
        var issues: [NoteConnectionIssue] = []
        for record in records {
            for title in Self.bodyTitles(record.body) {
                references.append(.init(sourceID: record.id, origin: .body, targetTitle: title, resolution: resolve(title)))
            }
            guard let type = record.declaredType, let fields = record.fields else { continue }
            for rule in rulesByType[type, default: []] {
                guard let field = fields[rule.field] else { continue }
                let values: [NoteFieldValue]
                if case .array(let array) = field { values = array } else { values = [field] }
                for value in values {
                    guard let string = value.string, let title = Self.exactTitle(string) else {
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

    private static func titleKey(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func exactTitle(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("[["), text.hasSuffix("]]"), text.count > 4 else { return nil }
        let title = text.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !title.contains("["), !title.contains("]"), !title.contains("\n"), !title.contains("\r") else { return nil }
        // Pipes and heading suffixes remain part of the exact title; they do not introduce alias semantics.
        return title
    }

    private static func bodyTitles(_ body: String) -> [String] {
        body.matches(of: /\[\[([^\[\]\r\n]+)\]\]/).compactMap { match in
            exactTitle(String(match.output.0))
        }
    }
}
