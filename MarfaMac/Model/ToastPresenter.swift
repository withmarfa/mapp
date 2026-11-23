import Foundation
import Observation

/// What one window's toast says, and for how long (`docs/components.md`). A window has one presenter, held by its
/// `DetailsPresentation`, which sits above the split view, so another workspace does not drop a toast and another window
/// never shows it. A new toast replaces the one showing. A toast leaves on its own after `duration`, waits while the
/// pointer is over it (`hold`), and leaves at once when Undo is used.
@Observable
final class ToastPresenter {
    /// One message, with the undo of the action it reports where there is one.
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        /// The name of an SF Symbol drawn before the message.
        let symbol: String?
        /// Performs the action's undo. Nil where the action cannot be undone, so no Undo is offered.
        let undo: (@MainActor () -> Void)?
    }

    /// The design system gives a toast no time of its own.
    static let standardDuration: Duration = .seconds(5)

    /// The toast showing, if any.
    private(set) var current: Toast?
    /// Whether the pointer is over the toast, which keeps it.
    private(set) var isHeld = false

    @ObservationIgnored private let duration: Duration
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(duration: Duration = ToastPresenter.standardDuration, clock: any Clock<Duration> = ContinuousClock()) {
        self.duration = duration
        self.clock = clock
    }

    /// Shows `message`, in place of any toast showing, with Undo where `undo` is given. Answers the toast's identity,
    /// for `dismiss(ifShowing:)`.
    @discardableResult
    func show(_ message: String, symbol: String? = nil, undo: (@MainActor () -> Void)? = nil) -> Toast.ID {
        let toast = Toast(message: message, symbol: symbol, undo: undo)
        current = toast
        isHeld = false
        startTimer(for: toast.id)
        return toast.id
    }

    /// Takes the toast away only while it is the one with `id`, so a toast that replaced it stays.
    func dismiss(ifShowing id: Toast.ID) {
        if current?.id == id { dismiss() }
    }

    /// Takes the toast away, whether it is held or not.
    func dismiss() {
        timer?.cancel()
        timer = nil
        isHeld = false
        current = nil
    }

    /// Runs the showing toast's undo once and takes the toast away. A toast that has gone, or one with no undo, does
    /// nothing, so a second press or a press as the toast leaves undoes nothing more.
    func undo() {
        guard let undo = current?.undo else { return }
        dismiss()
        undo()
    }

    /// Whether the pointer is over the toast. The time starts again, in full, when the pointer leaves.
    func hold(_ held: Bool) {
        guard let current, isHeld != held else { return }
        isHeld = held
        if held {
            timer?.cancel()
            timer = nil
        } else {
            startTimer(for: current.id)
        }
    }

    private func startTimer(for id: Toast.ID) {
        timer?.cancel()
        let clock = clock, duration = duration
        timer = Task { [weak self] in
            do { try await clock.sleep(for: duration) } catch { return }
            self?.expire(id)
        }
    }

    private func expire(_ id: Toast.ID) {
        guard current?.id == id, !isHeld else { return }
        dismiss()
    }
}
