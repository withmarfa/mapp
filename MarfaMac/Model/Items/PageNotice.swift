import Foundation

/// The one line a page says when something is not ordinary: its kind, its words and at most one action. Three
/// presenters draw it the same way, the web head (`editor/src/notice.ts`), the file page and the saved web page
/// (`PageNoticeView`), and none decides anything. `of(_:)` is the one table of which notice a state gives.
///
/// No action writes or drops text: Recover changes only the item's state, Open Copy opens another item, and Load
/// Pictures asks for pictures as each Load button does.
nonisolated struct PageNotice: Equatable, Sendable {
    /// In the order they win: a page says one thing at a time.
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
    }

    let kind: Kind
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
        case nil: nil
        }
    }

    /// How many pictures wait, for the pictures' notice.
    let waitingPictures: Int

    /// The symbols a presenter draws, for the page to be sent as images.
    static var symbols: [String] { Kind.allCases.map { PageNotice(kind: $0, words: "").symbol } }

    init(kind: Kind, words: String, reason: String? = nil, action: Action? = nil, waitingPictures: Int = 0) {
        self.kind = kind
        self.words = words
        self.reason = reason
        self.action = action
        self.waitingPictures = waitingPictures
    }

    /// What the page says of `item`, or nil where it needs to say nothing. `fileIsMissing` is the library having no file
    /// for an item that is one; `waitingPictures` is how many pictures of a saved web page wait for the person.
    static func of(_ item: Item, fileIsMissing: Bool = false, waitingPictures: Int = 0) -> PageNotice? {
        if item.state == .trashed {
            return PageNotice(
                kind: .deleted, words: String(localized: "Recently deleted items can’t be edited."), action: .recover)
        }
        if case .conflicted(let copy?, _) = item.sync {
            return PageNotice(
                kind: .copySaved, words: String(localized: "This item changed elsewhere, so your changes were saved as a copy."),
                action: .openCopy(copy))
        }
        if let problem = item.problem, problem.withholdsText {
            return PageNotice(
                kind: .unreadable, words: String(localized: "This item couldn’t be read on this Mac."), reason: problem.message)
        }
        if let held = item.heldWords {
            return PageNotice(kind: .held, words: held)
        }
        if let problem = item.problem {
            return PageNotice(kind: .syncProblem, words: problem.message)
        }
        if fileIsMissing {
            return PageNotice(kind: .fileMissing, words: String(localized: "This item’s file isn’t in Marfa."))
        }
        if waitingPictures > 0 {
            return PageNotice(
                kind: .picturesWaiting, words: Self.picturesWaiting(waitingPictures), action: .loadPictures,
                waitingPictures: waitingPictures)
        }
        return nil
    }

    static func picturesWaiting(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 picture from another website isn’t loaded.")
            : String(localized: "\(count) pictures from other websites aren’t loaded.")
    }
}

nonisolated extension Item {
    /// What the page says of a write the copy holds on this item, or nil where none is held. A write that waits is
    /// only on its way, and a refused key is the connection's to say.
    fileprivate var heldWords: String? {
        let problem: SyncProblem
        switch sync {
        case .refused(let held), .blocked(let held): problem = held
        case .settled, .waiting, .conflicted: return nil
        }
        if problem.code == BlockedReason.credentialRefused.rawValue, problem.grant == nil { return nil }
        if case .tooLarge(let size, let limit)? = problem.unsent {
            let (sizeText, limitText) = Words.sizes(size, limit)
            return String(localized: "This item is \(sizeText), more than the \(limitText) the server takes at once, so your changes haven’t reached it. Make it smaller to send them.")
        }
        let lead = String(localized: "Your changes to this item haven’t reached the server.")
        guard let message = problem.message, !message.isEmpty else { return lead }
        return lead + " " + Words.unsentReason(message)
    }
}

nonisolated extension PageNotice: Encodable {
    private enum Key: String, CodingKey { case kind, symbol, words, action, reason }

    /// What the web head draws. Its action's label only: the page says which kind was chosen.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(words, forKey: .words)
        try container.encodeIfPresent(actionLabel, forKey: .action)
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}
