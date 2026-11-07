import Foundation

/// The properties an item's page pins under its title, resolved to what each shows: the one model for every page that
/// draws pins, which takes nothing from the editor. The page draws what this returns and decides nothing.
///
/// The person's list (`PagePlacement.pins`) says which properties, in which order. A pin with nothing to show is left
/// out, with no placeholder: an empty status or parent is set from the inspector. A pin naming something the type or
/// the item does not have is left out the same way, and stays in the list. A pin never repeats what the header's own
/// line says (`PageHeaderLead.said`).
///
/// An event's time is its first pin, whatever the person chose. It takes one of the `pinLimit` slots, and a pin it
/// pushes out goes back to the property block, so nothing the item shows disappears.
nonisolated struct PagePins: Equatable, Sendable {
    /// Most values of a list a pin shows before "+N".
    static let listLimit = 2

    /// The pins to draw, in order.
    let pins: [PropertyRow]
    /// The rows the property block leaves out: every property pinned, drawn or not, so a pin is never also a row,
    /// and whatever the header's own line says. A pin the event's time pushed out stays in the block.
    let leftOutOfBlock: Set<String>

    /// `candidates` are the item's rows before any choice (`PropertyRow.candidates`). A pinned status is the pill the
    /// page draws from its status menu, and stays editable there; a pinned parent is a link that opens it, since
    /// only the row keeps the parent's menu. Every other pin opens its editor where its row does (`PropertyRow.editable`).
    static func resolve(
        for item: Item, type: ItemTypeInfo?, placement: PagePlacement, lead: PageHeaderLead, relationships: [ItemRelationship],
        candidates: [PropertyRow], parentField: String = PagePlacement.parent, icon: (ItemID) -> String?,
        isPerson: (ItemID) -> Bool
    ) -> PagePins {
        let said = lead.said
        let status = type?.statusField
        func row(for id: String) -> PropertyRow? {
            if id == parentField {
                return relationships.first { $0.field == parentField }.flatMap { PropertyRow.linkRow($0, icon: icon, isPerson: isPerson) }
            }
            guard let row = candidates.first(where: { $0.id == id }) else { return nil }
            if row.value == .status {
                // The pill shows a status the item has; one it has not is set from the inspector.
                return status.flatMap { statusValue(of: item, in: $0) } == nil ? nil : row
            }
            return row
        }
        let when = lead.event.map {
            PropertyRow(id: PagePlacement.when, label: String(localized: "When"), value: .when($0.time, help: $0.help))
        }
        let drawn = placement.pins.filter { !said.contains($0) }.compactMap(row(for:)).map(capped)
        let room = PagePlacement.pinLimit - (when == nil ? 0 : 1)
        let pushedOut = drawn.dropFirst(room).map(\.id)
        return PagePins(
            pins: [when].compactMap { $0 } + lead.refine(Array(drawn.prefix(room))),
            leftOutOfBlock: Set(placement.pins).union(said).subtracting(pushedOut))
    }

    /// The status the item holds, if it holds one.
    static func statusValue(of item: Item, in field: ItemTypeInfo.Field) -> String? {
        item.value(of: field.key)?.string.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A list shows its first `listLimit` values, and how many it left out.
    private static func capped(_ row: PropertyRow) -> PropertyRow {
        func cut<Value>(_ values: [Value], _ make: ([Value]) -> PropertyRow.Value) -> PropertyRow {
            guard values.count > listLimit else { return row }
            return PropertyRow(
                id: row.id, label: row.label, value: make(Array(values.prefix(listLimit))), numberToCall: row.numberToCall,
                more: values.count - listLimit, editable: row.editable)
        }
        switch row.value {
        case .items(let values): return cut(values) { .items($0) }
        case .people(let values): return cut(values) { .people($0) }
        case .options(let values): return cut(values) { .options($0) }
        case .tags(let values): return cut(values) { .tags($0) }
        default: return row
        }
    }
}
