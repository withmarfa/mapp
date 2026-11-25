import Foundation
import Marfa

/// What a card is for: an item a row, a foot row or a chip names by identity, or a link in the text, which only the core
/// can say what it means, read as authored.
nonisolated enum LinkCardTarget: Equatable, Sendable {
    case item(ItemID)
    case wiki(String)

    /// The page's `card` field: its kind and the identity or link it holds.
    init?(page value: Any?) {
        guard let dict = value as? [String: Any], let link = dict["link"] as? String, !link.isEmpty else { return nil }
        switch dict["kind"] as? String {
        case "item": self = .item(ItemID(link))
        case "wiki": self = .wiki(link)
        default: return nil
        }
    }
}

/// What the small card under the pointer says of a linked item: its type's mark and name, its own name and up to two
/// lines, worked out from what the copy holds and the counts Marfa last gave. A count not yet answered is left out, never
/// drawn as zero.
nonisolated struct LinkCardContent: Equatable, Sendable {
    /// The icon of the item's type, an Iconify ID.
    let icon: String?
    let typeName: String
    let title: String
    let lines: [String]

    /// The counts to ask for an item, which a card wants while it shows (`ItemCounts.want`): its children, and a
    /// collection's members.
    static func counts(for item: Item, in catalogue: Catalogue) -> [CountQuery] {
        catalogue.isCollection(item.type) ? [.children, .members] : [.children]
    }

    static func of(
        _ item: Item, in catalogue: Catalogue, counts: [CountQuery: ItemCountAnswer], format: DateFormat, now: Date = .now,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> LinkCardContent {
        var lines: [String] = []
        if let children = counts[.children], children.total > 0 {
            let completed = children.groups?.completed ?? 0
            lines.append(completed > 0
                ? String(localized: "\(Self.subItems(children.total)), \(completed) completed")
                : Self.subItems(children.total))
        }
        if let members = counts[.members], members.total > 0 {
            lines.append(members.total == 1 ? String(localized: "1 item") : String(localized: "\(members.total) items"))
        }
        func day(_ key: String) -> String? {
            item.value(of: key)?.string.flatMap { ItemDate.parse($0) }.map { $0.text(format: format, now: now, locale: locale, calendar: calendar) }
        }
        if let due = day(MarfaMapping.dueField) {
            lines.append(String(localized: "Due \(due)"))
        } else if let start = day(MarfaMapping.startField) {
            lines.append(String(localized: "Starts \(start)"))
        }
        return LinkCardContent(
            icon: catalogue.icon(for: item.type), typeName: catalogue.label(for: item.type), title: item.displayTitle,
            lines: Array(lines.prefix(2)))
    }

    private static func subItems(_ count: Int) -> String {
        count == 1 ? String(localized: "1 sub-item") : String(localized: "\(count) sub-items")
    }
}

extension ItemLibrary {
    /// The item a card may be drawn for: one the copy holds that is not in the bin and can be read. A missing or
    /// restricted item has none, so the pointer resting on it shows nothing.
    func cardItem(_ id: ItemID) -> Item? {
        guard let held = headerItem(id), held.state != .trashed, held.problem == nil else { return nil }
        return held
    }
}
