import Foundation

/// What a value of an item's property says: whether it is set, whether it is a yes, and the link it names. The title is the
/// page's heading and the text is the page's content, so neither is a property; the library says which keys it keeps for
/// itself (`ItemLibrary.hiddenPropertyKeys(of:)`).
nonisolated enum InspectorFields {
    /// Whether a value says anything. A cleared field reads as no value, whether the source drops it or keeps it
    /// empty.
    static func hasValue(_ value: PropertyValue?) -> Bool {
        switch value {
        case nil, .null: false
        case .string(let text)?: !text.isEmpty
        case .array(let values)?: !values.isEmpty
        case .object(let fields)?: !fields.isEmpty
        case .bool?, .number?, .double?: true
        }
    }

    /// Where a value is a link to: a web address of a url field, or a mail address of an email field. Only http,
    /// https and mailto are ever opened, so a stored `javascript:` or file address stays text.
    static func link(of field: ItemTypeInfo.Field, value: PropertyValue?) -> URL? {
        guard case .string(let raw)? = value else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field.format {
        case .url?:
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  url.host(percentEncoded: false)?.isEmpty == false
            else { return nil }
            return url
        case .email?:
            let parts = text.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }), !text.contains(where: { $0.isWhitespace }) else { return nil }
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = text
            return components.url
        case .currency?, nil:
            return nil
        }
    }

    /// Whether a yes/no property reads as checked: one that was never set, or has been cleared, is unchecked.
    static func isYes(_ value: PropertyValue?) -> Bool {
        if case .bool(true)? = value { true } else { false }
    }

    /// Every property the page lists elsewhere or never: what the type names, what is hidden, and the bookkeeping Marfa adds
    /// to an item.
    static func accountedFor(type: ItemTypeInfo?, hidden: Set<String>) -> Set<String> {
        Set((type?.fields ?? []).map(\.key)).union(hidden).union(["title", "type", "marfa_id", "marfa_version"])
    }
}
