import Foundation
import Observation
#if DEBUG
import Synchronization
#endif

/// Checks a batch before an import or attachment. The person's answer is the whole decision: nothing opened or
/// fetched afterwards changes which files are added.
@MainActor
enum AlreadyInMarfa {
    /// How long the whole check, hashing and lookup, may take before the files are added unasked.
    static let limit: Duration = .seconds(10)

    #if DEBUG
    /// Replaces `limit` for the check running in this task, including one a caller cannot pass a limit into, such as
    /// a paste. Another task's check is left at `limit`.
    @TaskLocal static var limitOverride: Duration?

    /// Counts a caller's security-scoped access. The check itself takes none: the caller holds the grant until the
    /// check, including one it cancelled, has ended.
    nonisolated struct GrantHooks: Sendable {
        var start: @Sendable (URL) -> Void
        var stop: @Sendable (URL) -> Void
    }

    /// Every registered watch hears each grant. A test adds its own and removes it when it ends, so another test's
    /// files are not mistaken for this one's and a watch is not replaced while a file is still held.
    nonisolated final class GrantWatch: Sendable {
        private let hooks = Mutex<[UUID: GrantHooks]>([:])

        func add(_ hooks: GrantHooks) -> UUID {
            let id = UUID()
            self.hooks.withLock { $0[id] = hooks }
            return id
        }

        func remove(_ id: UUID) {
            hooks.withLock { $0[id] = nil }
        }

        func start(_ url: URL) {
            let current = hooks.withLock { Array($0.values) }
            current.forEach { $0.start(url) }
        }

        func stop(_ url: URL) {
            let current = hooks.withLock { Array($0.values) }
            current.forEach { $0.stop(url) }
        }
    }

    /// Read from a file's access, which is not isolated to the main actor: releasing the file can happen as the value is destroyed.
    nonisolated static let grantWatch = GrantWatch()
    #endif

    enum Choice: Equatable, Sendable {
        case addAnyway
        case skipDuplicates
        case cancel
    }

    /// What to do with a batch once it has been checked. Positions are into the batch that was checked.
    struct Plan: Equatable {
        /// The files to add, in batch order. Final when the person answers.
        var adding: [Int]
        /// Items holding a file the person skipped, for Show after the add. Opening them changes nothing that was added.
        var show: [ItemID]
        /// Whether the person chose Cancel, so nothing at all is written.
        var isCancelled = false

        /// Every file is added, and nothing is offered to show.
        static func addingAll(count: Int) -> Plan {
            Plan(adding: Array(0..<count), show: [])
        }
    }

    /// What a toast says when files were left out because they are already in Marfa.
    static func skippedMessage(_ count: Int) -> String {
        if count == 1 { return String(localized: "1 file is already in Marfa.") }
        return String(localized: "\(count) files are already in Marfa.")
    }

    /// The same fact, after a toast that already says what was added.
    static func alreadyCounted(_ count: Int) -> String {
        if count == 1 { return String(localized: "1 is already in Marfa.") }
        return String(localized: "\(count) are already in Marfa.")
    }

    /// One question for a batch: the files already in Marfa, each with the items holding its bytes.
    struct Question: Identifiable, Equatable {
        struct Row: Equatable {
            /// Where this file stood in the batch. Two rows can name the same path.
            let index: Int
            let file: URL
            /// The items holding the file's bytes, by the names the window shows, Marfa's own order kept.
            let items: [(id: ItemID, name: String)]
            /// Whether Marfa holds more than it listed.
            let more: Bool

            static func == (lhs: Row, rhs: Row) -> Bool {
                lhs.index == rhs.index && lhs.file == rhs.file && lhs.items.map(\.id) == rhs.items.map(\.id) && lhs.more == rhs.more
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
                return String(localized: "“\(rows[0].file.lastPathComponent)” is already in Marfa.")
            }
            if rows.count == total {
                return String(localized: "\(rows.count) files are already in Marfa.")
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
        /// True after an alert is dismissed until the next one is allowed up. SwiftUI ignores a new question while one is up.
        @ObservationIgnored private var dismissalPending = false
        /// Runs inside `answer` when the person chooses Skip Duplicates, before the check goes on, so a draft can drop
        /// the matched files at that moment. Nil for an add that has no draft to change.
        @ObservationIgnored var onSkip: ((Question) -> Void)?

        /// The person's choice, or nil where no view could ask them.
        func ask(_ question: Question) async -> Choice? {
            guard views > 0 else { return nil }
            return await withCheckedContinuation { continuation in
                waiting.append((question, continuation))
                if self.question == nil, !dismissalPending { self.question = question }
            }
        }

        /// The person's choice for the question shown. One for another question, as from an alert already gone, is
        /// ignored. Skip Duplicates runs `onSkip` before this returns. The next question waits until this alert has gone.
        func answer(_ choice: Choice, to id: Question.ID? = nil) {
            guard let first = waiting.first, id == nil || first.question.id == id else { return }
            waiting.removeFirst()
            question = nil
            dismissalPending = true
            if choice == .skipDuplicates { onSkip?(first.question) }
            first.answer.resume(returning: choice)
            scheduleNext()
        }

        /// The alert wrote that it is no longer presented, so the next question may come up.
        func alertDismissed() { finishDismissal() }

        func viewAppeared() { views += 1 }

        /// The last view to show questions has gone, so what waits goes ahead unasked: the person chose nothing.
        func viewDisappeared() {
            views = max(views - 1, 0)
            guard views == 0 else { return }
            let unasked = waiting
            waiting = []
            question = nil
            dismissalPending = false
            for entry in unasked { entry.answer.resume(returning: nil) }
        }

        /// Lets the dismissal land, then shows what still waits. One turn is enough for the model; the alert's own
        /// dismissal calls `finishDismissal` as well, and the second finds nothing left to do.
        private func scheduleNext() {
            Task { @MainActor in
                await Task.yield()
                self.finishDismissal()
            }
        }

        private func finishDismissal() {
            guard dismissalPending, question == nil else { return }
            guard views > 0, let next = waiting.first else {
                dismissalPending = false
                return
            }
            dismissalPending = false
            question = next.question
        }
    }

    /// Checks `files` against what the library holds and, on a match, asks through `asking`. The caller keeps each
    /// file's access and any staged copy until this returns: a time-out cancels the lookup and waits until that
    /// cancelled lookup has ended, then every file is added. The caller takes no access here.
    static func check(_ files: [URL], in library: any ItemLibrary, asking: Asking, within requested: Duration = limit) async -> Plan {
        guard !files.isEmpty else { return .addingAll(count: 0) }
        #if DEBUG
        let limit = limitOverride ?? requested
        #else
        let limit = requested
        #endif
        let lookupTask = Task { @MainActor in
            await library.itemsWithSameBytes(as: files)
        }
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<LookupOutcome, Never>) in
            let gate = ResumeOnce(continuation)
            let timer = Task { @MainActor in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                lookupTask.cancel()
                gate.resume(.timedOut)
            }
            Task { @MainActor in
                let answers = await lookupTask.value
                timer.cancel()
                gate.resume(.answered(answers))
            }
        }
        switch outcome {
        case .answered(let answers):
            return await decide(files, answers: answers, in: library, asking: asking)
        case .timedOut:
            _ = await lookupTask.value
            return .addingAll(count: files.count)
        }
    }

    private enum LookupOutcome: Sendable {
        case answered(FileMatches)
        case timedOut
    }

    /// Resumes its continuation once. A late answer after a time-out is ignored.
    @MainActor private final class ResumeOnce<Value: Sendable> {
        private var continuation: CheckedContinuation<Value, Never>?

        init(_ continuation: CheckedContinuation<Value, Never>) {
            self.continuation = continuation
        }

        func resume(_ value: Value) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    private static func decide(
        _ files: [URL], answers: FileMatches, in library: any ItemLibrary, asking: Asking
    ) async -> Plan {
        let rows: [Question.Row] = files.enumerated().compactMap { index, file in
            guard case .answered(let matches, let more) = answers[index], !matches.isEmpty else { return nil }
            let items = matches.map { ($0.id, library.item($0.id)?.displayTitle ?? ($0.title.isEmpty ? String(localized: "Untitled") : $0.title)) }
            return Question.Row(index: index, file: file, items: items, more: more)
        }
        guard !rows.isEmpty else { return .addingAll(count: files.count) }
        switch await asking.ask(Question(rows: rows, total: files.count)) {
        case nil, .addAnyway:
            return .addingAll(count: files.count)
        case .skipDuplicates:
            let matched = Set(rows.map(\.index))
            var show: [ItemID] = []
            for id in rows.flatMap({ $0.items.map(\.id) }) where !show.contains(id) { show.append(id) }
            return Plan(adding: files.indices.filter { !matched.contains($0) }, show: show)
        case .cancel:
            return Plan(adding: [], show: [], isCancelled: true)
        }
    }
}
