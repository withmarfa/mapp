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
        if step.counterpartOf?.wasMade == false {
            return notices.tell(step.name, String(localized: "That change wasn’t made, so there is nothing to undo here."))
        }
        // Run by the undo manager, which has already taken the step off its stack. Anything else is an undo.
        within(UndoRun(step: step, undoing: step.manager?.isRedoing != true)) { step.handler(self) }
    }

    func within(_ run: UndoRun?, _ action: () -> Void) {
        let outer = undoRun
        undoRun = run
        defer { undoRun = outer }
        action()
    }

    /// The engine did not make a held step's writes, because what they touch changed or the copy was not brought up to
    /// date in time. An undo goes back on the undo stack, which empties the redo stack of the step it had registered;
    /// a redo cannot go back, so the undo it registered does nothing and says so.
    func giveBack(_ run: UndoRun, _ problem: SyncProblem, title: String?) {
        guard !run.told else { return }
        run.told = true
        run.outcome.wasMade = false
        let restoring = run.undoing && run.step.manager != nil
        if restoring {
            register(UndoStep(manager: run.step.manager!, name: run.step.name, handler: run.step.handler, counterpartOf: run.step.counterpartOf))
        }
        let again = restoring ? " " + String(localized: "Choose Undo again to try it as things are now.") : ""
        notices.tell(title ?? run.step.name, (problem.message ?? MarfaEngine.heldChanged) + again)
    }
}
