import Foundation

extension Browser {
    /// Whether the "Make something new" row of chips stands above the page: on the Sources and Collections indexes,
    /// and on Items while it shows in a layout that spans the window (the gallery, table, board or timeline), not once
    /// an item is open.
    var offersNewItemChips: Bool {
        if showsSettings { return false }
        return showsSidebarIndex || (item == .allNotes && showsCollection)
    }

    /// Opens a destination the sidebar, the menus and the palette list. Items opens in a layout that spans the window,
    /// so a window on the list moves to the gallery; the person's own choice of another layout stands.
    func choose(_ item: SidebarItem, in library: any ItemLibrary, order: NoteOrder) {
        if item == .allNotes, viewMode == .list { viewMode = .gallery }
        show(item, in: library, order: order)
    }
}

/// Which types the "Make something new" row offers as chips, and which wait under its More chip.
enum NewItemChips {
    static let shownCount = 4

    /// The types people hold most items of come first, then the rest in the order given. A type with no items still
    /// fills the row, so a new library has chips too.
    static func split(
        _ options: [ItemTypeOption], usedMost: [TypeID], limit: Int = shownCount
    ) -> (shown: [ItemTypeOption], more: [ItemTypeOption]) {
        var ordered = usedMost.compactMap { id in options.first { $0.id == id } }
        ordered += options.filter { option in !ordered.contains(option) }
        return (Array(ordered.prefix(limit)), Array(ordered.dropFirst(limit)))
    }
}
