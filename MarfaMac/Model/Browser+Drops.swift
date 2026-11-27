import Foundation

extension Browser {
    /// Files the dragged items under a collection, and says so in the window's toast with an Undo that takes the drop
    /// back. Items already in it get no second edge, and the toast counts them. An item that cannot join is told by
    /// the library. Returns whether the drop was taken.
    @discardableResult
    func addDropped(
        _ ids: Set<ItemID>, to collection: ItemID, in library: any ItemLibrary, undoManager: UndoManager?, toasts: ToastPresenter?
    ) -> Bool {
        guard !ids.isEmpty else { return false }
        let adding = library.collectionPlan(ids, joining: collection).joining
        let already = ids.filter { library.item($0)?.collectionIDs.contains(collection) == true }.count
        let title = library.item(collection)?.displayTitle ?? ""
        // A group with nothing in it still leaves the manager something to undo, so one opens only for a step.
        let run = adding.isEmpty ? nil : DropStep(undoManager)
        let taken = library.addToCollection(ids, collection, undoManager: undoManager)
        let step = run?.finish(named: String(localized: "Add to Collection"))
        guard taken else { return false }
        let message: String
        if adding.isEmpty {
            guard already > 0 else { return true }
            message = AttributedString(localized: "^[\(already) item](inflect: true) already in \(title)").text
        } else {
            let added = adding.count == 1
                ? String(localized: "Added “\(adding[0].displayTitle)” to \(title)")
                : AttributedString(localized: "^[Added \(adding.count) item](inflect: true) to \(title)").text
            message = already > 0 ? String(localized: "\(added), \(already) already in it") : added
        }
        say(message, symbol: "rectangle.stack.badge.plus", step: step, toasts: toasts)
        return true
    }

    /// Shows `message` in the toast, with Undo where `step` is still the undo manager's latest, and Show where
    /// `showMatches` opens items that were left out.
    func say(
        _ message: String, symbol: String, step: StepUndo?, showMatches: (@MainActor () -> Void)? = nil, toasts: ToastPresenter?
    ) {
        guard let toasts else { return }
        guard let step, step.isCurrent else {
            toasts.show(message, symbol: symbol, showMatches: showMatches)
            return
        }
        let id = toasts.show(message, symbol: symbol, undo: { step.perform() }, showMatches: showMatches)
        step.onLapse = { [weak toasts] in toasts?.dismiss(ifShowing: id) }
    }
}

/// The steps one drop registers, as one group of the undo manager, so that Undo takes the whole drop back. A manager
/// that groups by event already holds them in the group of the run loop's pass, which the drop never awaits across.
@MainActor
struct DropStep {
    private let undoManager: UndoManager?
    private let startsGroup: Bool
    private let opensGroup: Bool

    init(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
        startsGroup = undoManager?.groupingLevel == 0
        opensGroup = startsGroup && undoManager?.groupsByEvent == false
        if opensGroup { undoManager?.beginUndoGrouping() }
    }

    /// Closes the group, named `name`, and returns what the toast's Undo takes back: nil where the drop began inside
    /// another group, since Undo would take that group's other steps with it.
    func finish(named name: String) -> StepUndo? {
        // With no group open nothing was registered, which a drop the library refused leaves.
        if let undoManager, undoManager.groupingLevel > 0 { undoManager.setActionName(name) }
        if opensGroup { undoManager?.endUndoGrouping() }
        guard startsGroup, let undoManager, undoManager.canUndo else { return nil }
        return StepUndo(undoManager: undoManager)
    }
}
