import Foundation

nonisolated enum GallerySelection {
    static func selecting(_ id: ItemID, among ids: [ItemID], current: Set<ItemID>, anchor: ItemID?, extending: Bool, toggling: Bool) -> Set<ItemID> {
        guard let end = ids.firstIndex(of: id) else { return current }
        if extending, let anchor, let start = ids.firstIndex(of: anchor) {
            return Set(ids[min(start, end)...max(start, end)])
        }
        if toggling {
            var result = current
            if !result.insert(id).inserted { result.remove(id) }
            return result
        }
        return [id]
    }

    static func moving(from id: ItemID?, among ids: [ItemID], by offset: Int) -> ItemID? {
        guard !ids.isEmpty else { return nil }
        guard let id, let index = ids.firstIndex(of: id) else { return ids.first }
        return ids[min(max(0, index + offset), ids.count - 1)]
    }

    static func movingVertically(from id: ItemID?, sections: [[ItemID]], columns: Int, down: Bool) -> ItemID? {
        let count = max(1, columns)
        let rows = sections.flatMap { section in
            stride(from: 0, to: section.count, by: count).map { Array(section[$0..<min($0 + count, section.count)]) }
        }
        guard let id, let row = rows.firstIndex(where: { $0.contains(id) }), let column = rows[row].firstIndex(of: id) else { return rows.first?.first }
        let next = min(max(0, row + (down ? 1 : -1)), rows.count - 1)
        return rows[next][min(column, rows[next].count - 1)]
    }
}
