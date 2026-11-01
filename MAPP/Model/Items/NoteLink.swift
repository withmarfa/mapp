import Foundation
import Marfa

/// A `[[link]]` as the core reads it (`linkParts(in:)`): the name before any `|` or `#`, the heading after `#`, and
/// `raw`, the text between the brackets exactly as written. Marfa has no escape in a link, so a backslash is part of
/// the text; the page's own reading of one is never used.
///
/// `raw` defines equality, byte for byte as Marfa compares authored spellings, so `[[Plan]]` and `[[Plan|Plan]]` stay
/// distinct.
nonisolated struct NoteLink: Hashable, Sendable {
    let raw: String
    let name: String
    let heading: String?

    /// The link a text holds as a whole, such as `[[Plan#Goals|the plan]]`; nil where the core finds none.
    init?(linkText: String) {
        guard let parts = linkParts(in: linkText).first, parts.text == linkText else { return nil }
        raw = parts.target
        name = parts.name.text
        heading = parts.heading?.text
    }

    // Swift String equality normalizes Unicode; Marfa's authored binding keys compare bytes.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.raw.utf8.elementsEqual(rhs.raw.utf8) }

    func hash(into hasher: inout Hasher) {
        hasher.combine(raw.utf8.count)
        for byte in raw.utf8 { hasher.combine(byte) }
    }
}

/// What the core says a link names, from the copy alone (`Items.linkCandidates`). Only `bound` names one note: an
/// identity the copy holds, or a name the copy already bound. A name that one held note answers to stays
/// `unresolved`, since the copy holds a slice and the server may hold another note by that name; its `candidates`
/// say which. An `ambiguous` link has more than one.
nonisolated struct LinkAnswer: Hashable, Sendable {
    enum State: Hashable, Sendable { case bound, ambiguous, unresolved }

    /// The text between the link's brackets, as asked.
    let target: String
    let state: State
    /// The note a `bound` link names.
    let item: ItemID?
    /// Every note outside the bin the name answers to, including the bound one.
    let candidates: [ItemID]

    /// Whether no held note answers to the link at all.
    var isMissing: Bool { state == .unresolved && candidates.isEmpty }

    /// Whether the core binds the link to this note. Only that is a link written to name the note: an `unresolved`
    /// answer cannot tell that the one note held is the only one, so the server's lookup decides once the link is
    /// saved (`device/link-candidates-unresolved`).
    func names(_ note: ItemID) -> Bool { state == .bound && item == note }

    /// Whether this title is a fair offer for the note while the person types it: bound to it, or not bound and
    /// answered to by it alone among the notes held. The person sees the title and chooses it, and the server decides
    /// at the save, so an offer can end unresolved; a link written for the person (`names`) never relies on that.
    func offers(_ note: ItemID) -> Bool { names(note) || (state == .unresolved && candidates == [note]) }
}

/// An embed in an item's text with what the library bound it to: the file item it shows, or why there is none.
nonisolated struct BoundEmbed: Hashable, Sendable {
    /// The embed as the text holds it, such as `![[photo.png|400]]`, which is how the page names it too.
    let text: String
    let resolution: NoteReferenceResolution
}

/// Marfa trims Unicode White_Space, which excludes format characters such as U+200B.
nonisolated enum NoteName {
    static func trimmed(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
              let last = scalars.lastIndex(where: { !$0.properties.isWhitespace }) else { return "" }
        return String(String.UnicodeScalarView(scalars[first...last]))
    }

    /// The title of an item titled by its text: the first line that is not empty, trimmed of spaces.
    static func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// The text without the line `firstLine(of:)` reads, or the blank lines that follow it, so the title moved out
    /// of it is not left behind. Everything after is kept byte for byte.
    static func removingFirstLine(of text: String) -> String {
        guard let start = text.firstIndex(where: { !$0.isNewline }) else { return text }
        let end = text[start...].firstIndex(where: \.isNewline) ?? text.endIndex
        return String(text[end...].drop(while: \.isNewline))
    }
}

nonisolated enum NoteReferenceResolution: Hashable, Sendable {
    case resolved(ItemID)
    case missing
    case ambiguous([ItemID])
    /// Not looked up on the server yet.
    case pending
    /// The server refused the lookup or the write of the edge.
    case refused(String)
}
