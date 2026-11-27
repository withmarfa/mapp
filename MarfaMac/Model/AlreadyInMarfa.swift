import Foundation
import Observation

/// Checks a batch before an import or attachment. Only an explicit Open or Cancel can exclude a file.
@MainActor
enum AlreadyInMarfa {
    /// How long the whole check, hashing and lookup, may take before the files are added unasked.
    static let limit: Duration = .seconds(10)

    enum Choice: Equatable, Sendable {
        case addAnyway
        case open
        case cancel
    }

    /// What to do with a batch once it has been checked.
    struct Plan: Equatable {
        /// The files to add, in the order given.
        let add: [URL]
        /// The items already in Marfa to open in place of their files.
        let open: [ItemID]
        /// Whether the person chose Cancel, so nothing at all is written.
        var isCancelled = false

        /// Every file is added, with no question asked or Add Anyway chosen.
        static func addingAll(_ files: [URL]) -> Plan { Plan(add: files, open: []) }
    }

    /// One question for a batch: the files already in Marfa, each with the items holding its bytes.
    struct Question: Identifiable, Equatable {
        struct Row: Equatable {
            let file: URL
            /// The items holding the file's bytes, by the names the window shows, Marfa's own order kept.
            let items: [(id: ItemID, name: String)]
            /// Whether Marfa holds more than it listed.
            let more: Bool

            static func == (lhs: Row, rhs: Row) -> Bool {
                lhs.file == rhs.file && lhs.items.map(\.id) == rhs.items.map(\.id) && lhs.more == rhs.more
            }
        }

        let id = UUID()
        /// The files already in Marfa, in the order given.
        let rows: [Row]
        /// How many files the batch holds, matched or not.
        let total: Int

        /// How many files the message names one by one before it says how many more there are.
        static let listLimit = 5

        var title: String {
            if rows.count == 1, total == 1 {
                return String(localized: "“\(rows[0].file.lastPathComponent)” Is Already in Marfa")
            }
            if rows.count == total {
                return String(localized: "\(rows.count) Files Are Already in Marfa")
            }
            return String(localized: "\(rows.count) of \(total) Files Already in Marfa")
        }

        var message: String {
            if rows.count == 1, total == 1 { return Self.sentence(for: rows[0], named: nil) }
            var lines = rows.prefix(Self.listLimit).map { Self.sentence(for: $0, named: $0.file.lastPathComponent) }
            let rest = rows.count - Self.listLimit
            if rest > 0 { lines.append(AttributedString(localized: "And ^[\(rest) more file](inflect: true).").text) }
            return lines.joined(separator: "\n")
        }

        /// Names the file when the title does not. A truncated result has no exact count.
        private static func sentence(for row: Row, named file: String?) -> String {
            let first = row.items.first?.name ?? ""
            let others = row.items.count - 1
            switch (file, row.more, others) {
            case (nil, true, _):
                return String(localized: "It has the same contents as “\(first)” and other items.")
            case (nil, false, 0):
                return String(localized: "It has the same contents as “\(first)”.")
            case (nil, false, _):
                return AttributedString(localized: "It has the same contents as “\(first)” and ^[\(others) other item](inflect: true).").text
            case (let file?, true, _):
                return String(localized: "“\(file)” has the same contents as “\(first)” and other items.")
            case (let file?, false, 0):
                return String(localized: "“\(file)” has the same contents as “\(first)”.")
            case (let file?, false, _):
                return AttributedString(localized: "“\(file)” has the same contents as “\(first)” and ^[\(others) other item](inflect: true).").text
            }
        }
    }

    /// Where a question waits to be shown, one at a time, in the window, panel or page that the files were added in.
    /// A view shows `question` and gives the person's choice to `answer`. With no view to show it, as when the panel
    /// or window has gone, nothing is asked and the files are added as if Marfa had not answered.
    @Observable @MainActor final class Asking {
        /// The question to show now, the first of those waiting.
        private(set) var question: Question?
        @ObservationIgnored private var waiting: [(question: Question, answer: CheckedContinuation<Choice?, Never>)] = []
        @ObservationIgnored private var views = 0

        /// The person's choice, or nil where no view could ask them.
        func ask(_ question: Question) async -> Choice? {
            guard views > 0 else { return nil }
            return await withCheckedContinuation { continuation in
                waiting.append((question, continuation))
                if self.question == nil { self.question = question }
            }
        }

        /// The person's choice for the question shown. One for another question, as from an alert already gone, is
        /// ignored.
        func answer(_ choice: Choice, to id: Question.ID? = nil) {
            guard let first = waiting.first, id == nil || first.question.id == id else { return }
            waiting.removeFirst()
            question = waiting.first?.question
            first.answer.resume(returning: choice)
        }

        func viewAppeared() { views += 1 }

        /// The last view to show questions has gone, so what waits goes ahead unasked: the person chose nothing.
        func viewDisappeared() {
            views = max(views - 1, 0)
            guard views == 0 else { return }
            let unasked = waiting
            waiting = []
            question = nil
            for entry in unasked { entry.answer.resume(returning: nil) }
        }
    }

    /// Checks `files` against what the library holds and, on a match, asks through `asking`. Each file is read under
    /// its security scope while it is checked.
    static func check(_ files: [URL], in library: any ItemLibrary, asking: Asking, within limit: Duration = limit) async -> Plan {
        guard !files.isEmpty else { return .addingAll(files) }
        let scoped = files.filter { $0.startAccessingSecurityScopedResource() }
        let answers = await FirstAnswer.within(limit, otherwise: FileMatches.noAnswer) {
            await library.itemsWithSameBytes(as: files)
        }
        for file in scoped { file.stopAccessingSecurityScopedResource() }
        let rows: [Question.Row] = files.compactMap { file in
            guard case .answered(let matches, let more) = answers[file], !matches.isEmpty else { return nil }
            let items = matches.map { ($0.id, library.item($0.id)?.displayTitle ?? ($0.title.isEmpty ? String(localized: "Untitled") : $0.title)) }
            return Question.Row(file: file, items: items, more: more)
        }
        guard !rows.isEmpty else { return .addingAll(files) }
        switch await asking.ask(Question(rows: rows, total: files.count)) {
        case nil, .addAnyway:
            return .addingAll(files)
        case .open:
            let matched = Set(rows.map(\.file))
            var opening: [ItemID] = []
            for id in rows.flatMap({ $0.items.map(\.id) }) where !opening.contains(id) { opening.append(id) }
            return Plan(add: files.filter { !matched.contains($0) }, open: opening)
        case .cancel:
            return Plan(add: [], open: [], isCancelled: true)
        }
    }
}
