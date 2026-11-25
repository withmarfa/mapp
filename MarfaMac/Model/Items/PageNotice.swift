import Foundation

/// One line a page says when something is not ordinary: its kind, its words and at most one action. Three
/// presenters draw it the same way, the web head (`editor/src/notice.ts`), the file page and the saved web page
/// (`PageNoticeView`), and none decides anything. `all(for:)` is the one table of which lines a state gives.
///
/// No action writes or drops text: Recover changes only the item's state, Open Copy opens another item, Show Changes
/// opens the Settings page that lists the changes this Mac holds, and Load Pictures asks for pictures as each Load
/// button does. An action carries its item and its target from here, never from the page.
nonisolated struct PageNotice: Equatable, Sendable {
    /// In the order they win. A line of a state that hides text or a change (`unreadable`, `held`, `fileMissing`) is
    /// never hidden by another; the rest give way to the first that applies.
    enum Kind: String, CaseIterable, Sendable {
        case deleted
        case copySaved
        case unreadable
        case held
        case syncProblem
        case fileMissing
        case picturesWaiting
    }

    enum Action: Equatable, Sendable {
        case recover
        case openCopy(ItemID)
        case loadPictures
        /// Opens Settings where the changes the copy holds are listed and can be copied.
        case showChanges
    }

    let kind: Kind
    /// The item the page shows, which every action is for.
    let item: ItemID
    var words: String
    /// What the page's text would say, for a notice that withholds the text.
    var reason: String?
    var action: Action?

    /// Only the pictures' notice can be put away, for the page.
    var isClosable: Bool { kind == .picturesWaiting }

    /// The SF Symbol drawn before the words.
    var symbol: String {
        switch kind {
        case .deleted: "trash"
        case .copySaved: "doc.on.doc"
        case .unreadable, .held, .syncProblem: "exclamationmark.triangle"
        case .fileMissing: "questionmark.folder"
        case .picturesWaiting: "photo"
        }
    }

    /// The label of the action's text button.
    var actionLabel: String? {
        switch action {
        case .recover: String(localized: "Recover")
        case .openCopy: String(localized: "Open Copy")
        case .loadPictures: waitingPictures == 1 ? String(localized: "Load Picture") : String(localized: "Load Pictures")
        case .showChanges: String(localized: "Show Changes")
        case nil: nil
        }
    }

    /// How many pictures wait, for the pictures' notice.
    let waitingPictures: Int

    /// The symbols a presenter draws, for the page to be sent as images.
    static var symbols: [String] { Kind.allCases.map { PageNotice(kind: $0, item: ItemID(""), words: "").symbol } }

    init(kind: Kind, item: ItemID, words: String, reason: String? = nil, action: Action? = nil, waitingPictures: Int = 0) {
        self.kind = kind
        self.item = item
        self.words = words
        self.reason = reason
        self.action = action
        self.waitingPictures = waitingPictures
    }

    /// What the page says of `item`, top to bottom. The first of a deleted item, a copy saved beside it, values that
    /// could not be read and then pictures that wait leads, and the lines that would hide text or a change follow it
    /// whatever leads: text that cannot be read, a write the copy holds, and a file the library lacks. `fileIsMissing`
    /// is the library having no file for an item that is one; `waitingPictures` is how many pictures of a saved web
    /// page wait for the person.
    static func all(for item: Item, fileIsMissing: Bool = false, waitingPictures: Int = 0) -> [PageNotice] {
        let id = item.id
        var lines: [PageNotice] = []
        if item.state == .trashed {
            lines.append(
                PageNotice(
                    kind: .deleted, item: id, words: String(localized: "Recently deleted items can’t be edited."), action: .recover))
        } else if case .conflicted(let copy?, _) = item.sync {
            lines.append(
                PageNotice(
                    kind: .copySaved, item: id,
                    words: String(localized: "This item changed elsewhere, so your changes were saved as a copy."), action: .openCopy(copy)))
        }
        let lead = !lines.isEmpty
        if let problem = item.problem, problem.withholdsText {
            lines.append(
                PageNotice(
                    kind: .unreadable, item: id, words: String(localized: "This item couldn’t be read on this Mac."),
                    reason: problem.message))
        }
        let held = item.heldNotice
        if let held { lines.append(held) }
        if let problem = item.problem, !problem.withholdsText, !lead, held == nil {
            lines.append(PageNotice(kind: .syncProblem, item: id, words: problem.message))
        }
        if fileIsMissing {
            lines.append(PageNotice(kind: .fileMissing, item: id, words: String(localized: "This item’s file isn’t in Marfa.")))
        }
        if lines.isEmpty, waitingPictures > 0 {
            lines.append(
                PageNotice(
                    kind: .picturesWaiting, item: id, words: Self.picturesWaiting(waitingPictures), action: .loadPictures,
                    waitingPictures: waitingPictures))
        }
        return lines
    }

    static func picturesWaiting(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 picture from another website isn’t loaded.")
            : String(localized: "\(count) pictures from other websites aren’t loaded.")
    }
}

nonisolated extension Item {
    /// What the page says of a write the copy holds on this item, or nil where none is held. A write that waits is
    /// only on its way. A held write always has its line, with the copy's reason where it has one. Where a write was
    /// refused as too large, the page shows the older text and the person's latest is in no write the server has, so
    /// the line says where it is kept and offers to show it, whichever held write ranks first.
    fileprivate var heldNotice: PageNotice? {
        let problem: SyncProblem
        switch sync {
        case .refused(let held), .blocked(let held): problem = held
        case .settled, .waiting, .conflicted: return nil
        }
        let kept = String(localized: "Your latest changes were too large to save to Marfa. They’re kept on this Mac, where you can copy them.")
        if problem.isTooLarge { return PageNotice(kind: .held, item: id, words: kept, action: .showChanges) }
        var words = String(localized: "Your changes to this item haven’t reached the server.")
        if let message = problem.message, !message.isEmpty { words += " " + Words.unsentReason(message) }
        guard problem.alsoHoldsOversizedText else { return PageNotice(kind: .held, item: id, words: words) }
        return PageNotice(kind: .held, item: id, words: words + " " + kept, action: .showChanges)
    }
}

nonisolated extension PageNotice: Encodable {
    private enum Key: String, CodingKey { case kind, item, symbol, words, action, reason }

    /// What the web head draws. Its action's label only: the page says which kind was chosen, for the item named here.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(item.rawValue, forKey: .item)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(words, forKey: .words)
        try container.encodeIfPresent(actionLabel, forKey: .action)
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}
