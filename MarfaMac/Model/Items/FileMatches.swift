import Foundation

/// An item the person can read whose file holds the same bytes as a file about to be added, as Marfa names it.
nonisolated struct FileMatch: Hashable, Sendable {
    let id: ItemID
    /// The item's title as Marfa gave it, shown where the library does not hold the item.
    let title: String
}

/// What Marfa said of one file's bytes.
nonisolated enum FileMatchAnswer: Hashable, Sendable {
    /// Marfa answered: the items holding these bytes, empty where none does, and whether it holds more than it listed.
    case answered([FileMatch], more: Bool)
    /// There is no answer: the check failed, ran out of time or was never made. It is never read as "no match":
    /// the file is added as if nothing had been asked.
    case noAnswer
}

/// The answers for a batch, one per file in the order asked. A position Marfa gave no answer for is `noAnswer`.
/// The same path can be asked twice and get two answers, so a result is never stored by its URL.
nonisolated struct FileMatches: Sendable, Equatable {
    private var answers: [FileMatchAnswer]

    init(_ answers: [FileMatchAnswer]) {
        self.answers = answers
    }

    /// No file answered, as where the library cannot ask or the check failed.
    static let noAnswer = FileMatches([])

    subscript(position: Int) -> FileMatchAnswer {
        answers.indices.contains(position) ? answers[position] : .noAnswer
    }
}
