import Foundation
import Observation

/// A new view's title, from the moment the panel opens until the server takes it. A refusal leaves the title as
/// typed, so the person can try again or cancel, and a title the window takes away before the server took it is
/// given back through `Notices.notKept`.
@Observable
final class ViewTitleForm {
    enum Outcome: Equatable {
        /// The server took the title and made the view.
        case done(LibraryView)
        /// The library refused it and told the person why; the title stays for another try.
        case refused
    }

    /// Why the window stops asking for the title before the server took it.
    enum Departure {
        case closed
        case libraryChanged
        /// The panel closed or the window moved to another place.
        case left
    }

    var title: String
    private(set) var isSaving = false
    private let library: any ItemLibrary
    private var isFinished = false
    private var departure: Departure?

    init(title: String = "", library: any ItemLibrary) {
        self.title = title
        self.library = library
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Whether a view is being made or was made from this form, so another Done has nothing to do.
    var isBusy: Bool { isSaving || isFinished }

    var canSubmit: Bool { !isSaving && !isFinished && !trimmedTitle.isEmpty && library.reachesServer }

    /// Makes the view of `draft` under the title, and keeps the title for another try if the server refuses it.
    func submit(_ draft: ViewDraft.Draft) async -> Outcome {
        guard canSubmit else { return .refused }
        isSaving = true
        defer { isSaving = false }
        let settings = LibraryViewSettings(title: trimmedTitle, query: draft.query, sort: draft.sort, group: draft.group)
        if let view = await library.createView(settings) {
            isFinished = true
            return .done(view)
        }
        giveBack()
        return .refused
    }

    /// The person's own Cancel: the title is theirs to drop, so nothing is given back. Any other end of the panel
    /// is a `handOff`.
    func discard() {
        isFinished = true
    }

    /// Gives a title the server has not taken to the clipboard through the library's notices, as the panel that
    /// asked for it ends without the person's Cancel. A title on its way to the server is given back only if it is refused.
    func handOff(because departure: Departure) {
        guard !isFinished, self.departure == nil else { return }
        self.departure = departure
        guard !isSaving else { return }
        giveBack()
    }

    private func giveBack() {
        guard let departure, !isFinished else { return }
        isFinished = true
        let title = trimmedTitle
        guard !title.isEmpty else { return }
        let reason = switch departure {
        case .closed: String(localized: "The window closed before the view was saved.")
        case .libraryChanged: String(localized: "The window changed to another library before the view was saved.")
        case .left: String(localized: "The panel closed before the view was saved.")
        }
        library.notices.notKept(String(localized: "View Not Saved"), text: title, reason: reason)
    }
}
