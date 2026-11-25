import Foundation

extension Browser {
    /// Runs a move on `ids` and says so in the window's toast, with an Undo that takes back that move. The toast waits
    /// for the library's answer, so it names only what the copy queued, and shows nothing where nothing moved. The
    /// toast's Undo is the step the move registered (`StepUndo`), so it is the undo manager's own Undo: where the move's
    /// writes are not yet answered, the library puts it back on the stack and says so. It is offered only where no undo
    /// group was open before the move, as Delete's is. `moved` hears the same answer.
    static func move(
        _ move: ItemMove, _ ids: Set<ItemID>, beneath: Bool = false, in library: any ItemLibrary, undoManager: UndoManager?,
        toasts: ToastPresenter?, moved: ((CommandOutcome) -> Void)? = nil
    ) {
        let startsGroup = undoManager?.groupingLevel == 0
        let opensGroup = startsGroup && undoManager?.groupsByEvent == false
        let report = MoveReport(move, library: library, toasts: toasts)
        let answer = { (outcome: CommandOutcome) in
            report.answer(outcome)
            moved?(outcome)
        }
        if opensGroup { undoManager?.beginUndoGrouping() }
        switch move {
        case .keep: library.setTier(ids, to: .library, undoManager: undoManager, moved: answer)
        case .moveToFeed: library.setTier(ids, to: .feed, undoManager: undoManager, moved: answer)
        case .archive: library.archive(ids, beneath: beneath, undoManager: undoManager, moved: answer)
        case .unarchive: library.unarchive(ids, undoManager: undoManager, moved: answer)
        }
        if opensGroup { undoManager?.endUndoGrouping() }
        report.begin(step: startsGroup ? undoManager.flatMap { $0.canUndo ? StepUndo(undoManager: $0) : nil } : nil)
    }
}

/// What a move says in the toast once the library has answered and the move's undo step is known, whichever comes first.
@MainActor
private final class MoveReport {
    private let move: ItemMove
    private let library: any ItemLibrary
    private weak var toasts: ToastPresenter?
    private var step: StepUndo?
    private var outcome: CommandOutcome?
    private var isBegun = false

    init(_ move: ItemMove, library: any ItemLibrary, toasts: ToastPresenter?) {
        self.move = move
        self.library = library
        self.toasts = toasts
    }

    func answer(_ outcome: CommandOutcome) {
        self.outcome = outcome
        show()
    }

    func begin(step: StepUndo?) {
        self.step = step
        isBegun = true
        show()
    }

    private func show() {
        guard isBegun, let outcome, outcome.changed > 0, let toasts else { return }
        self.outcome = nil
        let message = library.movedMessage(move, outcome)
        guard let step, step.isCurrent else {
            toasts.show(message, symbol: move.symbol)
            return
        }
        let id = toasts.show(message, symbol: move.symbol, undo: { step.perform() })
        step.onLapse = { [weak toasts] in toasts?.dismiss(ifShowing: id) }
    }
}
