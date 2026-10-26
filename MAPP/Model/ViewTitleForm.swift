import Foundation
import Observation

/// A new view's title, or a view's new name, from the moment its sheet opens until the server takes it. A refusal
/// leaves the title as typed, so the person can try again or cancel, and a title the window takes away before the
/// server took it is given back through `Notices.notKept`.
@Observable
final class ViewTitleForm {
    enum Purpose {
        /// A new view of what the window shows, and the layout the window shows it in.
        case new(ViewDraft.Draft, layout: ItemViewMode)
        case rename(ItemID)
    }

    enum Outcome: Equatable {
        /// The server took the title, or a rename left the name as it was (nil); the sheet closes.
        case done(LibraryView?)
        /// The library refused it and told the person why; the title stays for another try.
        case refused
    }

    let purpose: Purpose
    var title: String
    private(set) var isSaving = false
    /// The name the view had when the sheet opened.
    private let originalTitle: String
    /// The version of the view the sheet opened on, which a rename is based on.
    private var baseVersion: Int64
    private var needsRebase = false
    private let library: any ItemLibrary
    private var isFinished = false
    private var departure: QuickAdd.Departure?

    init(new draft: ViewDraft.Draft, layout: ItemViewMode, title: String, library: any ItemLibrary) {
        purpose = .new(draft, layout: layout)
        self.title = title
        originalTitle = ""
        baseVersion = 0
        self.library = library
        Self.open.add(self)
    }

    init(renaming view: LibraryView, library: any ItemLibrary) {
        purpose = .rename(view.id)
        title = view.title
        originalTitle = view.title
        baseVersion = view.version
        self.library = library
        Self.open.add(self)
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSubmit: Bool { !isSaving && !isFinished && !trimmedTitle.isEmpty && library.canEditViews }

    /// Sends the title to the server, and keeps it for another try if the server refuses it.
    func submit() async -> Outcome {
        guard canSubmit else { return .refused }
        let title = trimmedTitle
        isSaving = true
        defer { isSaving = false }
        switch purpose {
        case .new(let draft, _):
            let settings = LibraryViewSettings(title: title, query: draft.query, sort: draft.sort, group: draft.group)
            if let view = await library.createView(settings) { return finish(view) }
        case .rename(let id):
            guard title != originalTitle else { return finish(nil) }
            if needsRebase, let current = library.views.first(where: { $0.id == id }) { baseVersion = current.version }
            switch await library.changeView(id, LibraryViewChange(title: title), baseVersion: baseVersion) {
            case .success(let view): return finish(view)
            // The person has been told the view changed elsewhere, so trying again renames the view as it is now.
            case .failure(let failure): needsRebase = failure.kind == .conflict
            }
        }
        giveBack()
        return .refused
    }

    private func finish(_ view: LibraryView?) -> Outcome {
        isFinished = true
        return .done(view)
    }

    /// Gives a title the server has not taken to the clipboard through the library's notices, as the window that
    /// asked for it closes or changes library. A title on its way to the server is given back only if it is refused.
    func handOff(because departure: QuickAdd.Departure) {
        guard !isFinished, self.departure == nil else { return }
        self.departure = departure
        guard !isSaving else { return }
        giveBack()
    }

    private func giveBack() {
        guard let departure, !isFinished else { return }
        isFinished = true
        let title = trimmedTitle
        guard !title.isEmpty, title != originalTitle else { return }
        let isNew = if case .new = purpose { true } else { false }
        let reason = switch (departure, isNew) {
        case (.closed, true): String(localized: "The window closed before the view was saved.")
        case (.closed, false): String(localized: "The window closed before the view was renamed.")
        case (.libraryChanged, true): String(localized: "The window changed to another library before the view was saved.")
        case (.libraryChanged, false): String(localized: "The window changed to another library before the view was renamed.")
        }
        library.notices.notKept(
            isNew ? String(localized: "View Not Saved") : String(localized: "View Not Renamed"), text: title, reason: reason)
    }

    /// Every form still open, so a quit can give back each title.
    private static let open = NSHashTable<ViewTitleForm>.weakObjects()

    /// Gives back every title the server has not taken, as the app quits.
    static func handOffAll() {
        for form in open.allObjects { form.handOff(because: .closed) }
    }
}
