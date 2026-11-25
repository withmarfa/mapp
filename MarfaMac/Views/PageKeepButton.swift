import SwiftUI

/// Keep, the word that leads an item's toolbar while the item is in the Feed: it moves the item to the Library as the
/// Keep in Library command does (`ItemLibrary.perform`). `kept` runs only once the copy has queued the move for this
/// item; where it refuses, the page stays and the toast or notice says why.
struct PageKeepButton: View {
    @CurrentLibrary private var library
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let id: ItemID
    let undoManager: UndoManager?
    var kept: () -> Void = {}

    /// Whether the item is one Keep applies to: an item in the Feed.
    static func applies(to id: ItemID, in library: any ItemLibrary) -> Bool {
        library.selectionCommands([id]).contains(.keep)
    }

    /// Keeps the item, and runs `kept` once the copy has queued the move for it, never before or on a refusal.
    static func keep(
        _ id: ItemID, in library: any ItemLibrary, undoManager: UndoManager?, details: DetailsPresentation?,
        then kept: @escaping () -> Void
    ) {
        library.perform(.keep, on: [id], undoManager: undoManager, details: details) { outcome in
            if outcome.onlyItem == id { kept() }
        }
    }

    var body: some View {
        if Self.applies(to: id, in: library) {
            Button("Keep", systemImage: ItemMove.keep.symbol) {
                Self.keep(id, in: library, undoManager: undoManager, details: details, then: kept)
            }
            .help(Text(ItemMove.keep.name))
            .accessibilityIdentifier("PageKeep")
        }
    }
}
