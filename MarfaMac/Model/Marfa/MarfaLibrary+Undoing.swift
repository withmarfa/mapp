import Foundation

/// The undo manager takes a step off its stack before it runs the step, so an Undo or Redo the copy refuses while it
/// is brought up to date would be gone. The writes a step makes are marked as the step's (`ItemSource.submit`'s
/// `undoing`), so the engine holds them until the copy is whole (`MarfaEngine+Holding`). If it then does not make them,
/// the step is put back here so the person can choose it again.
extension MarfaLibrary {
    /// One step the undo manager holds: what it is called and what it does.
    final class UndoStep {
        weak var manager: UndoManager?
        let name: String
        let handler: (MarfaLibrary) -> Void
        /// The step that registered this one while it ran, so this one does nothing if that step was not made.
        let counterpartOf: UndoRun.Outcome?

        init(manager: UndoManager, name: String, handler: @escaping (MarfaLibrary) -> Void, counterpartOf: UndoRun.Outcome?) {
            self.manager = manager
            self.name = name
            self.handler = handler
            self.counterpartOf = counterpartOf
        }
    }

    /// One time the undo manager ran a step.
    final class UndoRun {
        /// Whether the step's writes were made, which the step it registered in return depends on.
        final class Outcome {
            var wasMade = true
        }

        let group = UndoGroup()
        let step: UndoStep
        let undoing: Bool
        let outcome = Outcome()
        var told = false

        init(step: UndoStep, undoing: Bool) {
            self.step = step
            self.undoing = undoing
        }
    }

    func registerUndo(_ undoManager: UndoManager?, name: String, _ handler: @escaping (MarfaLibrary) -> Void) {
        guard let undoManager else { return }
        register(UndoStep(manager: undoManager, name: name, handler: handler, counterpartOf: undoRun?.outcome))
    }

    private func register(_ step: UndoStep) {
        guard let manager = step.manager else { return }
        manager.registerUndo(withTarget: self) { library in library.run(step) }
        manager.setActionName(step.name)
    }

    private func run(_ step: UndoStep) {
        // Run by the undo manager, which has already taken the step off its stack. Anything else is an undo.
        let run = UndoRun(step: step, undoing: step.manager?.isRedoing != true)
        within(run) {
            guard step.counterpartOf?.wasMade != false else { return notices.tell(step.name, notMade) }
            step.handler(self)
        }
    }

    /// Tells the person that the step run undoes or redoes a change that was not made.
    var notMade: String {
        undoRun?.undoing == false
            ? String(localized: "That change wasn’t made, so there is nothing to redo here.")
            : String(localized: "That change wasn’t made, so there is nothing to undo here.")
    }

    func within(_ run: UndoRun?, _ action: () -> Void) {
        let outer = undoRun
        undoRun = run
        defer { undoRun = outer }
        action()
    }

    /// A held step's writes were not made, because what they touch changed or the copy was not brought up to date in
    /// time. An undo goes back on the undo stack. This happens after its run, and registering outside an undo or redo
    /// empties the whole redo stack, the step it had registered included. A redo cannot go back, so the undo it
    /// registered does nothing and says so. A redo's write that carried the person's text is the only copy of it, so
    /// `text` is kept where they can get it back, as for a library that closed.
    func giveBack(_ run: UndoRun, _ problem: SyncProblem, title: String?, text: String?) {
        let first = !run.told
        run.told = true
        run.outcome.wasMade = false
        let restoring = run.undoing && run.step.manager != nil
        let title = title ?? run.step.name
        let message = problem.message ?? MarfaEngine.heldChanged
        if restoring, first {
            register(UndoStep(manager: run.step.manager!, name: run.step.name, handler: run.step.handler, counterpartOf: run.step.counterpartOf))
        }
        if !restoring, text?.isEmpty == false {
            notices.notKept(title, text: text, reason: message)
        } else if first {
            let again = restoring ? " " + String(localized: "Choose Undo again to try it as things are now.") : ""
            notices.tell(title, message + again)
        }
    }

    /// A property Undo that can be made once an earlier edit is answered, refused while it runs
    /// (`MarfaLibrary+PropertyEdits`). It goes back on the undo stack once its run has ended, as a held step given back
    /// does (`giveBack`), which empties the redo stack. Redoing what the run registered instead would make again every
    /// other step of its undo group.
    func putBack(_ run: UndoRun, reason: String) {
        run.outcome.wasMade = false
        run.told = true
        notices.tell(run.step.name, reason + " " + String(localized: "Choose Undo again to try it as things are now."))
        guard let manager = run.step.manager else { return }
        let step = UndoStep(manager: manager, name: run.step.name, handler: run.step.handler, counterpartOf: run.step.counterpartOf)
        Task { [weak self] in
            guard let self else { return }
            // A manager that does not group by event takes a step only inside a group it was asked to open.
            let opens = !manager.groupsByEvent && manager.groupingLevel == 0
            if opens { manager.beginUndoGrouping() }
            register(step)
            if opens { manager.endUndoGrouping() }
        }
    }
}
