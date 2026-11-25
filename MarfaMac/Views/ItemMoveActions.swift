import SwiftUI

/// Several items waiting for the person to choose whether Archive takes what is under them too, with the undo manager
/// of the window they were asked for in.
struct ArchiveRequest: Identifiable {
    let id = UUID()
    let ids: Set<ItemID>
    /// The name of the one item chosen, where one was.
    let title: String?
    /// How many active items are under the chosen ones.
    let beneath: Int
    let undoManager: UndoManager?
}

/// Items waiting for the person to confirm Move to Feed, which the Feed would let go.
struct FeedLimitRequest: Identifiable {
    let id = UUID()
    let ids: Set<ItemID>
    let title: String?
    let question: FeedLimitQuestion
    let undoManager: UndoManager?
}

extension ItemMove {
    /// The command whose key the menu bar binds. Archive and Unarchive are one command, which toggles by state.
    var shortcutCommand: ShortcutCommand {
        switch self {
        case .keep: .keepInLibrary
        case .moveToFeed: .moveToFeed
        case .archive, .unarchive: .archive
        }
    }
}

extension ItemLibrary {
    /// Runs `move` on `ids`, or asks first where it must: Archive of items that hold others, and Move to Feed of items
    /// the Feed would let go. The question belongs to `details`' window. Without one nothing can ask, so Archive takes
    /// only the chosen items and Move to Feed goes ahead.
    func perform(_ move: ItemMove, on ids: Set<ItemID>, undoManager: UndoManager?, details: DetailsPresentation?) {
        func titleOfOne() -> String? { ids.count == 1 ? ids.first.flatMap { item($0)?.name } : nil }
        if let details {
            switch move {
            case .moveToFeed:
                if let question = feedLimitQuestion(for: ids) {
                    details.feedLimit = FeedLimitRequest(ids: ids, title: titleOfOne(), question: question, undoManager: undoManager)
                    return
                }
            case .archive:
                let beneath = archivePlan(ids).beneath.count
                if beneath > 0 {
                    details.archiving = ArchiveRequest(ids: ids, title: titleOfOne(), beneath: beneath, undoManager: undoManager)
                    return
                }
            case .keep, .unarchive:
                break
            }
        }
        Browser.move(move, ids, in: self, undoManager: undoManager, toasts: details?.toasts)
    }
}

/// Keep in Library, Move to Feed and Archive or Unarchive for the selection. A row's menu lists the moves that would
/// change something, so a selection in both tiers lists both tier moves. The menu bar and the More menu keep all three in
/// place, dimmed where nothing would change.
struct ItemMoveActions: View {
    @CurrentLibrary private var library
    /// The window's, which asks the questions; the menu bar passes the front window's in.
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let ids: Set<ItemID>
    let undoManager: UndoManager?
    var keepsPlace = false
    var shortcuts: ShortcutBindings?

    var body: some View {
        let offered = library.selectionCommands(ids)
        // Archive is the one command for a mixed selection; Unarchive only where nothing in it can be archived.
        let toggle: ItemMove = offered.contains(.unarchive) && !offered.contains(.archive) ? .unarchive : .archive
        let moves: [ItemMove] = keepsPlace ? [.keep, .moveToFeed, toggle] : library.menuMoves(ids)
        ForEach(moves, id: \.self) { move in
            Button(move.name, systemImage: move.symbol) {
                library.perform(move, on: ids, undoManager: undoManager, details: details)
            }
            .shortcut(move.shortcutCommand, shortcuts)
            .disabled(!offered.contains(move))
        }
    }
}

extension View {
    /// Asks the person whether Archive takes what is under the items, for the window whose presentation it is given.
    func archiveQuestion(for details: DetailsPresentation) -> some View {
        modifier(ArchiveQuestion(details: details))
    }

    /// Asks the person to confirm Move to Feed of items the Feed would let go, for the window whose presentation it is given.
    func feedLimitQuestion(for details: DetailsPresentation) -> some View {
        modifier(FeedLimitQuestionAlert(details: details))
    }
}

private struct ArchiveQuestion: ViewModifier {
    @CurrentLibrary private var library
    let details: DetailsPresentation

    func body(content: Content) -> some View {
        content.alert(
            details.archiving.map { MoveWords.archiveTitle(selected: $0.ids.count, title: $0.title, beneath: $0.beneath) } ?? "",
            isPresented: Binding { details.archiving != nil } set: { if !$0 { details.archiving = nil } },
            presenting: details.archiving
        ) { request in
            Button("Archive All") {
                Browser.move(.archive, request.ids, beneath: true, in: library, undoManager: request.undoManager, toasts: details.toasts)
            }
            .keyboardShortcut(.defaultAction)
            Button(MoveWords.archiveOnly(selected: request.ids.count)) {
                Browser.move(.archive, request.ids, in: library, undoManager: request.undoManager, toasts: details.toasts)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(MoveWords.archiveMessage)
        }
    }
}

private struct FeedLimitQuestionAlert: ViewModifier {
    @CurrentLibrary private var library
    let details: DetailsPresentation

    func body(content: Content) -> some View {
        content.alert(
            details.feedLimit.map { MoveWords.feedTitle(selected: $0.ids.count, title: $0.title) } ?? "",
            isPresented: Binding { details.feedLimit != nil } set: { if !$0 { details.feedLimit = nil } },
            presenting: details.feedLimit
        ) { request in
            Button("Cancel", role: .cancel) {}
            Button("Move to Feed", role: .destructive) {
                Browser.move(.moveToFeed, request.ids, in: library, undoManager: request.undoManager, toasts: details.toasts)
            }
        } message: { request in
            Text(MoveWords.feedMessage(selected: request.ids.count, pastWindow: request.question.pastWindow))
        }
    }
}
