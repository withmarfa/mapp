import Foundation
import Observation

/// A new item typed where it will stand: a table's last row, New; a card at the top of a board's lane; a block dragged
/// on the calendar's week. It holds what its place implies (`Browser.inPlaceValues`) and what was typed, which
/// `NewItemDrafts` keeps at every change under the slot of its layout and place, so a scroll, a sync, a change of place,
/// a closed window, a quit or a refusal never loses it.
///
/// Escape drops an empty row and keeps a typed one, which stays in sight. Leaving the row adds it, as Return does, and
/// the item stands where it was typed until the row is left (`RowHold.added`).
@MainActor @Observable
final class InPlaceRow {
    /// Where the row is typed.
    nonisolated enum Spot: Hashable, Sendable {
        /// A table's last row, joining the group under the pointer, or the first.
        case table(group: String?)
        /// The top of a board's lane.
        case lane(ItemBoardLane.ID)
        /// A block on the calendar's week, from its start to its end.
        case block(start: Date, end: Date)

        /// The layout the row belongs to, which names its slot.
        var layout: String {
            switch self {
            case .table: "table"
            case .lane: "board"
            case .block: "calendar"
            }
        }
    }

    /// The slot a row's draft is kept under: one for each layout of a place, so each finds only its own.
    static func slot(_ spot: Spot, in place: PlaceView) -> NewItemDrafts.Slot {
        .inPlace("\(spot.layout):\(place.storageKey)")
    }

    private(set) var place: PlaceView?
    private(set) var spot: Spot?
    private(set) var draft: QuickAdd.Draft?
    /// Whether the row has the keyboard. A typed row that Escape left stays in sight without it.
    var isEditing = false
    /// Why a kept draft came back: the library refused it, or the app quit while it was being added.
    var notice: String?
    /// The draft may be in Marfa already, as the app quit while it was being added, so its next add asks first.
    private(set) var mayBeInMarfa = false
    /// The row asked whether to add again a draft that may be in Marfa already, so the next add makes it.
    private(set) var askedAgain = false
    /// While the create is being made, so a second add does nothing.
    private(set) var isSaving = false
    /// Where the draft is kept, which a test replaces with its own.
    @ObservationIgnored var drafts = NewItemDrafts.standard()
    @ObservationIgnored private(set) var entry: UUID?

    var slot: NewItemDrafts.Slot? {
        guard let spot, let place else { return nil }
        return Self.slot(spot, in: place)
    }

    /// Whether the row holds anything typed.
    var holdsContent: Bool { draft?.hasContent == true }

    /// Starts the row at `spot` in `place` of `library`: the draft a refusal gave back, else the one a closed window or an
    /// earlier run left in the slot, else `make`'s. Answers whether a kept draft came back.
    @discardableResult
    func begin(_ spot: Spot, in place: PlaceView, library: any ItemLibrary, make: () -> QuickAdd.Draft?) -> Bool {
        if self.place == place, let current = self.spot, current.layout == spot.layout, draft != nil {
            self.spot = spot
            return false
        }
        leave()
        drafts.notices = library.notices
        drafts.settle(in: library)
        let slot = Self.slot(spot, in: place)
        if let kept = drafts.takeReturned(slot, in: library.serverKey) ?? drafts.take(slot, in: library.serverKey) {
            self.place = place
            self.spot = spot
            entry = kept.id
            draft = kept.draft
            mayBeInMarfa = kept.interrupted
            notice = kept.interrupted ? QuickAdd.mayBeInMarfaNotice
                : kept.returned ? String(localized: "The item wasn’t added. What you typed is back.") : nil
            return true
        }
        guard let made = make() else { return false }
        self.place = place
        self.spot = spot
        entry = drafts.make(slot, made, in: library.serverKey)
        draft = made
        mayBeInMarfa = false
        notice = nil
        return false
    }

    /// Takes the slot's kept draft into sight without the keyboard, where the row holds none: one Escape left, or one a
    /// closed window or an earlier run kept.
    func restore(_ spot: Spot, in place: PlaceView, library: any ItemLibrary) {
        guard draft == nil || self.place != place, library.isLoaded, !library.serverKey.isEmpty else { return }
        drafts.settle(in: library)
        guard drafts.holdsDraft(Self.slot(spot, in: place), in: library.serverKey) else { return }
        begin(spot, in: place, library: library) { nil }
        isEditing = false
    }

    /// Changes what the row holds, as typing or a moved spot does. Kept at once.
    func change(_ edit: (inout QuickAdd.Draft) -> Void) {
        guard var changed = draft else { return }
        edit(&changed)
        guard changed != draft else { return }
        draft = changed
        guard let entry else { return }
        // A draft on its way is frozen; what is typed after it is a new one.
        self.entry = drafts.update(entry, changed)
    }

    /// Escape: an empty row goes, and a typed one stays in sight, kept, without the keyboard.
    func escape() {
        guard let entry else { return clear() }
        if drafts.escape(entry) {
            isEditing = false
        } else {
            drafts.release(entry)
            clear()
        }
    }

    /// The row's window went, or the window went on to another place or library. The draft stays kept for the next to
    /// take.
    func leave() {
        if let entry {
            if draft?.hasContent == true { drafts.release(entry) } else { drafts.drop(entry) }
        }
        clear()
    }

    private func clear() {
        entry = nil
        draft = nil
        place = nil
        spot = nil
        isEditing = false
        notice = nil
        mayBeInMarfa = false
        askedAgain = false
        isSaving = false
    }

    // MARK: Adding

    /// Kept as sent before the create is made, so a crash or a held-up write never makes it twice. False where the
    /// draft is kept nowhere, so nothing is sent.
    func willCreate(_ item: ItemID) -> Bool {
        guard let entry, drafts.sending(entry, as: item) else { return false }
        isSaving = true
        return true
    }

    /// The library made nothing, so the draft stays as typed.
    func notCreated() {
        isSaving = false
        if let entry { drafts.notSent(entry) }
    }

    /// The draft was added as `item`: kept until the library holds it (`NewItemDrafts.added`), and the row starts again
    /// empty at the same spot with `next`, or ends.
    func added(as item: ItemID, next: QuickAdd.Draft?, library: any ItemLibrary) {
        isSaving = false
        guard let entry, let spot, let place else { return }
        drafts.added(entry, as: item)
        self.entry = nil
        mayBeInMarfa = false
        notice = nil
        guard let next else { return clear() }
        self.entry = drafts.make(Self.slot(spot, in: place), next, in: library.serverKey)
        draft = next
    }

    /// Whether a draft that may be in Marfa already is added now: the first add asks, under the row, and the next makes it.
    func mayAdd() -> Bool {
        guard mayBeInMarfa else { return true }
        guard askedAgain else {
            askedAgain = true
            notice = String(localized: "This may already be in Marfa. The app quit while it was being added. Press Return again to add it.")
            return false
        }
        mayBeInMarfa = false
        askedAgain = false
        return true
    }

    /// Takes back the draft the library refused, where the row holds nothing typed, and says why it came back.
    func takeBackRefused(in library: any ItemLibrary) {
        guard !holdsContent, let slot, let place, let spot else { return }
        drafts.settle(in: library)
        guard let kept = drafts.takeReturned(slot, in: library.serverKey) else { return }
        if let entry { drafts.drop(entry) }
        self.place = place
        self.spot = spot
        entry = kept.id
        draft = kept.draft
        notice = String(localized: "The item wasn’t added. What you typed is back.")
    }
}
