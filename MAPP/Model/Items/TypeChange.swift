import Foundation

/// What changing an item's type writes in its one edit. Marfa keeps a property the new type does not declare and
/// reads the title and text from the new type's own keys (`device/body-retype`), so the title and the text move to
/// those keys in the same edit: none is left only under a key the page no longer reads, none is written twice, and
/// none is dropped.
nonisolated struct TypeChange: Hashable, Sendable {
    /// Why an item cannot become a type.
    enum Obstacle: Error, Hashable, Sendable {
        /// The item has text, or a title that would have to go into its text, and the type keeps no text.
        case noPlaceForText
        /// A required field of a shape MAPP does not edit, such as a list.
        case cannotFill(ItemTypeInfo.Field)
        /// A value the item holds does not fit the new type's field of that key.
        case valueDoesNotFit(ItemTypeInfo.Field)
    }

    /// A nil value removes the property.
    var changes: [String: PropertyValue?]
    /// The new type's required fields the item has no value for and `filling` gives none, in the type's order.
    var missing: [ItemTypeInfo.Field]
    /// The keys the item keeps that the new type does not declare, by key.
    var unused: [String]

    /// `values` are the item's properties with its text under the key its type keeps it in. `filling` gives
    /// values for required fields the item lacks; a value for any other key is ignored.
    static func plan(
        _ values: [String: PropertyValue], from old: ItemTypeInfo?, to new: ItemTypeInfo,
        filling: [String: PropertyValue] = [:]
    ) -> Result<TypeChange, Obstacle> {
        // A type the catalogue lacks is read as Marfa reads one with no hints: the title in `title`, no text.
        let oldTitleKey = old == nil ? "title" : old?.titleKey
        let oldBodyKey = old?.bodyKey
        let oldBody = oldBodyKey.flatMap { values[$0]?.string } ?? ""
        var body = oldBody
        var removed: Set<String> = []
        var set: [String: PropertyValue] = [:]

        switch (oldTitleKey, new.titleKey) {
        case let (from?, to?) where from != to:
            // A different title already under the new key, as another app may leave, is the one the new type reads,
            // and the old one stays under its own key, so neither is lost.
            let held = values[to]
            let free = held == nil || held == .null || held?.string.map({ NoteName.trimmed($0).isEmpty }) == true
            if let value = values[from],
               free || held?.string.map(NoteName.trimmed) == value.string.map(NoteName.trimmed) {
                if free { set[to] = value }
                removed.insert(from)
            }
        case (let from?, nil):
            if values[from] != nil { removed.insert(from) }
            // The title is kept as the text's first line, where the new type reads it.
            let title = NoteName.trimmed(values[from]?.string ?? "")
            if !title.isEmpty, NoteName.firstLine(of: body) != title {
                body = body.isEmpty ? title : title + "\n\n" + body
            }
        case (nil, let to?):
            // The first line becomes the title and leaves the text, unless the item already holds a title there.
            let title = NoteName.firstLine(of: body)
            let held = values[to]?.string.map(NoteName.trimmed) ?? ""
            if !title.isEmpty, held.isEmpty {
                set[to] = .string(title)
                body = NoteName.removingFirstLine(of: body)
            }
        default:
            break
        }

        if let to = new.bodyKey {
            if let from = oldBodyKey, from != to, values[from] != nil { removed.insert(from) }
            if oldBodyKey != to || body != oldBody {
                // Text the item already holds under the new key, which its old type did not read, is kept after it.
                if oldBodyKey != to, let held = values[to]?.string, !held.isEmpty, held != body {
                    body = body.isEmpty ? held : body + "\n\n" + held
                }
                if !body.isEmpty || values[to] != nil || oldBodyKey.flatMap({ values[$0] }) != nil {
                    set[to] = .string(body)
                }
            }
        } else {
            guard body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.noPlaceForText) }
            if let from = oldBodyKey, values[from] != nil { removed.insert(from) }
        }

        var result = values
        for key in removed { result[key] = nil }
        for (key, value) in set { result[key] = value }

        var missing: [ItemTypeInfo.Field] = []
        for field in new.fields where field.required {
            let held = result[field.key]
            let empty = held == nil || held == .null
                || (field.key == new.titleKey && NoteName.trimmed(held?.string ?? "").isEmpty)
            guard empty else { continue }
            if field.key == new.bodyKey, field.kind == .text {
                set[field.key] = .string("")
                result[field.key] = .string("")
            } else if case .other = field.kind {
                return .failure(.cannotFill(field))
            } else if let value = filling[field.key], field.kind.accepts(value),
                      field.key != new.titleKey || !NoteName.trimmed(value.string ?? "").isEmpty {
                set[field.key] = value
                result[field.key] = value
            } else {
                missing.append(field)
            }
        }

        // A value that fit the old type's field may not fit the new one's, which the server would refuse.
        for field in new.fields {
            guard let value = result[field.key], value != .null else { continue }
            if case .other = field.kind { continue }
            if let before = old?.fields.first(where: { $0.key == field.key }), before.kind == field.kind,
               set[field.key] == nil { continue }
            if !field.kind.accepts(value) { return .failure(.valueDoesNotFit(field)) }
        }

        var changes: [String: PropertyValue?] = [:]
        for key in removed where set[key] == nil { changes[key] = .some(nil) }
        for (key, value) in set where values[key] != value { changes[key] = value }
        let unused = result.filter { key, value in
            guard !new.declares(key) else { return false }
            return value != .null && value != .string("")
        }.keys.sorted()
        return .success(TypeChange(changes: changes, missing: missing, unused: unused))
    }
}

/// What the type change sheet shows for a set of items and a type.
nonisolated struct TypeChangePreview: Hashable, Sendable {
    /// The required fields to ask for, once each, in the new type's order.
    var missing: [ItemTypeInfo.Field]
    /// The labels of the fields the items keep that the new type does not use, in order.
    var unused: [String]
}

extension ItemLibrary {
    /// What a type change reads of an item: its properties, and its text under the key its type keeps it in. Nil
    /// for an item whose type MAPP cannot change: a file, one in the bin or with a problem, or one whose text is
    /// not read yet.
    func typeChangeValues(of id: ItemID) -> [String: PropertyValue]? {
        guard let item = item(id), item.isEditable else { return nil }
        var values = Dictionary(item.properties.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        if let bodyKey = catalogue.itemTypes[item.type]?.bodyKey {
            guard let body = body(of: id) else { return nil }
            values[bodyKey] = .string(body.text)
        }
        return values
    }

    /// The plan for one item, or nil where it cannot become `type`.
    func typeChange(of id: ItemID, to type: TypeID, filling: [String: PropertyValue] = [:]) -> TypeChange? {
        guard let item = item(id), let new = catalogue.itemTypes[type], item.type != type,
              !catalogue.isFileType(type), let values = typeChangeValues(of: id)
        else { return nil }
        return try? TypeChange.plan(values, from: catalogue.itemTypes[item.type], to: new, filling: filling).get()
    }

    /// Whether the item's type can be changed now: an item `typeChangeValues` reads.
    func canChangeType(_ id: ItemID) -> Bool {
        guard let item = item(id), item.isEditable else { return false }
        return catalogue.itemTypes[item.type]?.bodyKey == nil || body(of: id) != nil
    }

    /// The types at least one of `ids` can become, by label: those a new item can be, except the type the item
    /// already is. Empty where none of them can change type. A short selection is read type by type, and each type
    /// stops at the first item that can become it, so a long one costs little to ask.
    func typeChangeOptions(for ids: Set<ItemID>) -> [ItemTypeOption] {
        let candidates = ids.filter(canChangeType)
        guard !candidates.isEmpty else { return [] }
        return creatableTypes.filter { option in
            candidates.contains { id in item(id)?.type != option.id && typeChange(of: id, to: option.id) != nil }
        }
    }

    /// Whether `typeChangeOptions(for:)` has anything to offer, which stops at the first item that can become another
    /// type, so a selection of every item in the library costs little to ask.
    func offersTypeChange(for ids: Set<ItemID>) -> Bool {
        let options = creatableTypes
        return ids.contains { id in
            canChangeType(id) && options.contains { option in item(id)?.type != option.id && typeChange(of: id, to: option.id) != nil }
        }
    }

    /// What changing `ids` to `type` writes for each item that can become it, and the items it leaves out with the
    /// reason. An item already of `type` is neither. `missing` is the required fields some item still lacks, once
    /// each: the change is not made until they are given.
    func typeChangePlan(_ ids: Set<ItemID>, to type: TypeID, filling: [String: PropertyValue] = [:]) -> TypeChangePlan {
        var result = TypeChangePlan()
        let new = catalogue.itemTypes[type]
        for id in ids.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let item = item(id) else {
                result.skips.skip(.gone)
                continue
            }
            guard item.type != type else { continue }
            if let reason = item.writeObstacle {
                result.skips.skip(reason)
            } else if item.isFile {
                result.skips.skip(.file)
            } else if let new, !catalogue.isFileType(type), let values = typeChangeValues(of: id),
                      case .success(let plan) = TypeChange.plan(
                        values, from: catalogue.itemTypes[item.type], to: new, filling: filling) {
                if plan.missing.isEmpty {
                    result.items.append(TypeChangePlan.Entry(item: item, plan: plan, values: values))
                } else {
                    for field in plan.missing where !result.missing.contains(where: { $0.key == field.key }) {
                        result.missing.append(field)
                    }
                }
            } else {
                result.skips.skip(typeChangeValues(of: id) == nil ? .cantChange : .cantBecomeType)
            }
        }
        return result
    }

    /// What changing `ids` to `type` asks for and leaves unused, across all of them.
    func typeChangePreview(for ids: Set<ItemID>, to type: TypeID) -> TypeChangePreview {
        var missing: [ItemTypeInfo.Field] = []
        var unused: [String] = []
        for id in ids.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let item = item(id), let plan = typeChange(of: id, to: type) else { continue }
            for field in plan.missing where !missing.contains(where: { $0.key == field.key }) { missing.append(field) }
            for key in plan.unused {
                let label = ItemTypeInfo.Field.displayLabel(catalogue.label(ofField: key, for: item.type) ?? key)
                if !unused.contains(label) { unused.append(label) }
            }
        }
        let order = catalogue.itemTypes[type]?.fields.map(\.key) ?? []
        missing.sort { (order.firstIndex(of: $0.key) ?? .max) < (order.firstIndex(of: $1.key) ?? .max) }
        return TypeChangePreview(missing: missing, unused: unused.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }
}

/// What a change of type writes for each item that takes it (`ItemLibrary.typeChangePlan`).
struct TypeChangePlan {
    struct Entry {
        let item: Item
        let plan: TypeChange
        /// The item's values as the plan read them, for the undo.
        let values: [String: PropertyValue]
    }

    var items: [Entry] = []
    var skips = BatchSkips()
    var missing: [ItemTypeInfo.Field] = []
}
