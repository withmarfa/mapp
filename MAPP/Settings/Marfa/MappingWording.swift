import Foundation

/// What the mapping screen says, in the owner's words. The server's own sentence is shown only where it names a fault no
/// word of ours covers.
enum MappingWording {
    /// A field's name as a row's title: the label the server shows it by, else its name in title case.
    static func fieldTitle(_ field: MappingTypeField) -> String {
        ConnectorWording.settingTitle(field.label ?? field.name.replacing("_", with: " "))
    }

    /// A status word as a row's title: "in_progress" is "In Progress".
    static func word(_ word: String) -> String { ConnectorWording.kindTitle(word) }

    /// The row a refusal belongs on when no control on the page shows it.
    static func faultTitle(_ path: String) -> String {
        switch path {
        case "target_type": String(localized: "As")
        case "tier": String(localized: "To")
        case "enabled": String(localized: "Bring In")
        case "status_overrides": String(localized: "Status Words")
        default: word(path.split(separator: ".").last.map(String.init) ?? path)
        }
    }

    static func group(_ group: String) -> String { word(group) }

    /// Whether a field of one sort of value can fill a field of another.
    static func fits(_ source: MappingFieldKind, into target: MappingFieldKind) -> Bool {
        func family(_ kind: MappingFieldKind) -> Int {
            switch kind {
            case .string, .url, .email: 0
            case .number, .integer: 1
            case .datetime, .date: 2
            case .boolean: 3
            case .choice: 4
            case .array: 5
            case .object: 6
            case .thumbnail: 7
            case .status: 8
            }
        }
        return family(source) == family(target)
    }

    /// What a field the target type needs says when nothing fills it.
    static func needs(_ type: String, field: String) -> String {
        String(localized: "\(type) needs \(field). Choose a field or a fixed value.")
    }

    /// Under a failed save: the stored mapping did not change.
    static func kept(_ server: String) -> String {
        String(localized: "\(server) kept the mapping as it was.")
    }

    static func previewRefused(_ failure: OwnerFailure) -> String {
        if case .refused = failure { return String(localized: "The preview waits until the mapping can be saved.") }
        return OwnerWording.line(failure)
    }

    /// A draft that was not saved, in words the owner can read and type again.
    static func summary(_ mapping: KindMapping) -> String {
        var lines = [
            mapping.enabled ? String(localized: "On") : String(localized: "Off"),
            String(localized: "Type: \(mapping.targetType)"),
            String(localized: "Tier: \(mapping.tier.title)"),
        ]
        for (name, source) in mapping.fields.sorted(by: { $0.key < $1.key }) {
            switch source {
            case .field(let from): lines.append("\(name): \(from)")
            case .fixed(let value): lines.append("\(name): \(ConnectorsModel.text(value))")
            case .template(let text): lines.append("\(name): \(text)")
            }
        }
        for (word, target) in mapping.statusOverrides.sorted(by: { $0.key < $1.key }) { lines.append("\(word) → \(target)") }
        return lines.joined(separator: "\n")
    }

    /// A rewrite's request, as a row's title and line.
    static func pendingTitle(_ rewrite: PendingRewrite, plural: String) -> String {
        String(localized: "Applying to \(plural)")
    }

    static func pendingLine(_ rewrite: PendingRewrite, connector: String) -> String {
        if let when = OwnerWording.when(rewrite.requested) {
            return String(localized: "Asked \(when). \(connector) does it at its next run.")
        }
        return String(localized: "\(connector) does it at its next run.")
    }
}
