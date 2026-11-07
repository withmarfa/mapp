import SwiftUI

/// Opens Version History for one item, in the window whose presentation it is given. It stays available offline and
/// for a deleted item, since Version History says plainly what it can't show.
struct VersionHistoryButton: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    let details: DetailsPresentation?

    var body: some View {
        Button("Version History…", systemImage: "clock.arrow.circlepath") {
            if let id = ids.first { details?.showHistory(of: id, in: library) }
        }
        .disabled(
            details == nil || details?.history != nil || ids.count != 1 || ids.first.flatMap { library.item($0) } == nil)
    }
}

/// Exit Version History and Restore Version, which the menu bar offers only while the window in front shows Version
/// History. The toolbar has the same two buttons.
struct VersionHistoryCommands: View {
    let details: DetailsPresentation?
    let library: (any ItemLibrary)?
    let undoManager: UndoManager?

    var body: some View {
        let history = details?.history
        Button("Exit Version History", systemImage: "xmark") { details?.leaveHistory() }
            .disabled(history == nil)
        Button("Restore Version", systemImage: "arrow.uturn.backward") {
            if let details, let library { details.restoreFromHistory(in: library, undoManager: undoManager) }
        }
        .disabled(history == nil || library.map { history?.canRestore(in: $0) != true } ?? true)
    }
}
