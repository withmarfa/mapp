import Foundation
import Observation

/// Checks a batch before an import or attachment. Only an explicit Open or Cancel can exclude a file.
@MainActor
enum AlreadyInMarfa {
    /// How long the whole check, hashing and lookup, may take before the files are added unasked.
    static let limit: Duration = .seconds(10)

    #if DEBUG
    /// Replaces security-scoped access for a test, which an ordinary file on disk does not take.
    nonisolated struct AccessHooks: Sendable {
        var start: @Sendable (URL) -> Bool
        var stop: @Sendable (URL) -> Void
    }

    static let accessHooks = TestHook<AccessHooks>()
    /// Replaces `limit` for a caller that has no other way to pass one, such as a paste.
    static let limitOverride = TestHook<Duration>()
    #endif

    enum Choice: Equatable, Sendable {
        case addAnyway
        case open
        case cancel
    }

    /// How long a cancelled lookup may keep the add waiting before the add goes on with its own access.
    static let cancelGrace: Duration = .milliseconds(200)

    /// What to do with a batch once it has been checked.
    struct Plan: Equatable {
        /// The files to add, in the order given. A matched file whose item could not be opened is not here yet.
        let add: [URL]
        /// The items already in Marfa to open in place of their files.
        let open: [ItemID]
        /// Whether the person chose Cancel, so nothing at all is written.
        var isCancelled = false
        /// Each matched file and the items holding it, so one that cannot be opened is added instead.
        var matched: [Match] = []
        /// Positions in the checked batch that are added before a match that could not be opened is put back.
        var adding: [Int] = []
        /// Finishes when the lookup has ended, including one cancelled after a time-out. Equality ignores it.
        var lookup: Lookup = .finished

        /// A file already in Marfa, and the items that hold its bytes. `index` is its place in the batch.
        struct Match: Equatable, Sendable {
            let index: Int
            let file: URL
            let items: [ItemID]
        }

        /// The lookup's lifetime. Two plans compare equal whatever their lookups are doing.
        final class Lookup: @unchecked Sendable {
            private let task: Task<Void, Never>

            init(_ task: Task<Void, Never>) { self.task = task }

            func ended() async { await task.value }

            static let finished = Lookup(Task {})
        }

        static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.add == rhs.add && lhs.open == rhs.open && lhs.isCancelled == rhs.isCancelled
                && lhs.matched == rhs.matched && lhs.adding == rhs.adding
        }

        /// Every file is added, with no question asked or Add Anyway chosen.
        static func addingAll(_ files: [URL]) -> Plan {
            Plan(add: files, open: [], adding: Array(files.indices))
        }

        /// Positions to add: those already chosen, then each fallback match, in batch order.
        func indicesToAdd(fallback: [Match]) -> [Int] {
            var chosen = Set(adding)
            for match in fallback { chosen.insert(match.index) }
            return chosen.sorted()
        }
    }

    /// What opening a batch of matches managed: the items now open, and the matches to add instead.
    struct Opened: Equatable, Sendable {
        var opened: [ItemID]
        var fallback: [Plan.Match]
    }

    /// Brings each item into the library. Those it holds afterwards can be opened; the rest are added.
    /// An item that leaves while a later one is fetched is missed, so its file is added.
    static func reachable(_ ids: [ItemID], in library: any ItemLibrary) async -> (open: [ItemID], missed: [ItemID]) {
        var open: [ItemID] = []
        var missed: [ItemID] = []
        for id in ids {
            if library.item(id) != nil {
                open.append(id)
            } else if await library.holdForOpening(id) {
                open.append(id)
            } else {
                missed.append(id)
            }
        }
        let left = open.filter { library.item($0) == nil }
        if !left.isEmpty {
            open.removeAll { library.item($0) == nil }
            missed.append(contentsOf: left)
        }
        return (open, missed)
    }

    /// Opens each match. A match whose items are all missed comes back in `fallback`, beside its file.
    static func opening(_ matches: [Plan.Match], in library: any ItemLibrary) async -> Opened {
        var ids: [ItemID] = []
        for match in matches {
            for id in match.items where !ids.contains(id) { ids.append(id) }
        }
        let reached = await reachable(ids, in: library)
        let missed = Set(reached.missed)
        let fallback = matches.filter { !$0.items.isEmpty && $0.items.allSatisfy { missed.contains($0) } }
        return Opened(opened: reached.open, fallback: fallback)
    }

    /// What a toast or a notice says when matched files were added because their items could not be opened.
    static func unopenedMessage(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 file was added because the item already in Marfa couldn’t be opened.")
        }
        return String(localized: "\(count) files were added because the items already in Marfa couldn’t be opened.")
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
            if rows.count > 1 { lines.append(String(localized: "Open shows matches for all \(rows.count) files.")) }
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

        /// The person's choice, or nil where no view could ask them.
        func ask(_ question: Question) async -> Choice? {
            guard views > 0 else { return nil }
            return await withCheckedContinuation { continuation in
                waiting.append((question, continuation))
                if self.question == nil, !dismissalPending { self.question = question }
            }
        }

        /// The person's choice for the question shown. One for another question, as from an alert already gone, is
        /// ignored. The next question waits until this alert has gone.
        func answer(_ choice: Choice, to id: Question.ID? = nil) {
            guard let first = waiting.first, id == nil || first.question.id == id else { return }
            waiting.removeFirst()
            question = nil
            dismissalPending = true
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

    /// Checks `files` against what the library holds and, on a match, asks through `asking`. Each file is read under
    /// its security scope while it is checked. A time-out cancels the lookup. Access stays until that lookup has
    /// finished, but only for `cancelGrace` before the add goes on and the lookup releases access itself.
    static func check(_ files: [URL], in library: any ItemLibrary, asking: Asking, within limit: Duration = limit) async -> Plan {
        guard !files.isEmpty else { return .addingAll(files) }
        let scoped = files.filter { beginAccess($0) }
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
            for file in scoped { endAccess(file) }
            return await decide(files, answers: answers, in: library, asking: asking)
        case .timedOut:
            let finished = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let gate = ResumeOnce(continuation)
                Task { @MainActor in
                    _ = await lookupTask.value
                    gate.resume(true)
                }
                Task { @MainActor in
                    try? await Task.sleep(for: cancelGrace)
                    gate.resume(false)
                }
            }
            if finished {
                for file in scoped { endAccess(file) }
                return .addingAll(files)
            }
            let pending = Task { @MainActor in
                _ = await lookupTask.value
                for file in scoped { endAccess(file) }
            }
            var plan = Plan.addingAll(files)
            plan.lookup = Plan.Lookup(pending)
            return plan
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
        guard !rows.isEmpty else { return .addingAll(files) }
        switch await asking.ask(Question(rows: rows, total: files.count)) {
        case nil, .addAnyway:
            return .addingAll(files)
        case .open:
            let matched = Set(rows.map(\.index))
            var opening: [ItemID] = []
            for id in rows.flatMap({ $0.items.map(\.id) }) where !opening.contains(id) { opening.append(id) }
            let adding = files.indices.filter { !matched.contains($0) }
            return Plan(
                add: adding.map { files[$0] }, open: opening,
                matched: rows.map { Plan.Match(index: $0.index, file: $0.file, items: $0.items.map(\.id)) },
                adding: Array(adding))
        case .cancel:
            return Plan(add: [], open: [], isCancelled: true)
        }
    }

    private static func beginAccess(_ url: URL) -> Bool {
        #if DEBUG
        if let hooks = accessHooks.current { return hooks.start(url) }
        #endif
        return url.startAccessingSecurityScopedResource()
    }

    private static func endAccess(_ url: URL) {
        #if DEBUG
        if let hooks = accessHooks.current {
            hooks.stop(url)
            return
        }
        #endif
        url.stopAccessingSecurityScopedResource()
    }
}
