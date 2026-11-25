import Foundation

/// The writes the engine skips as it queues them (`MarfaEngine.judge`) are told together for each command or step,
/// in one notice with their count, once each of its writes has its first answer.
extension MarfaLibrary {
    /// The skips of one command or step, and its writes still waiting for their first answer.
    final class SkipNotice {
        let failing: String
        var skips = BatchSkips()
        /// Whether the copy took any of its writes.
        var changed = false
        /// The item each write moves, and those whose write the copy took.
        var items: [WriteID: ItemID] = [:]
        var queued: Set<ItemID> = []
        var waiting: Set<WriteID> = []
        var isOpen = true
        var answered: ((SkipNotice) -> Void)?

        init(failing: String) {
            self.failing = failing
        }
    }

    /// Runs `command`, gathering what it and the engine skip into one notice titled `failing` where nothing changed.
    /// `answered` runs once every write has its first answer.
    func gatheringSkips(failing title: String, answered: ((SkipNotice) -> Void)? = nil, _ command: () -> Void) {
        let outer = gathering
        let notice = SkipNotice(failing: title)
        notice.answered = answered
        gathering = notice
        command()
        gathering = outer
        notice.isOpen = false
        tellIfAnswered(notice)
    }

    /// The item is skipped by the command being gathered.
    func skip(_ reason: BatchSkips.Reason) {
        gathering?.skips.skip(reason)
    }

    /// Includes a submitted write while the engine decides whether to queue it.
    func gather(_ write: WriteID) {
        guard let notice = gathering else { return }
        notice.waiting.insert(write)
        skipNotices[write] = notice
    }

    /// The first answer to `write`: taken, where `outcome` is nil, or answered before the copy took it. True where it
    /// was a skip its command tells.
    @discardableResult
    func gatherAnswer(_ write: WriteID, _ outcome: WriteOutcome?) -> Bool {
        guard let notice = skipNotices.removeValue(forKey: write) else { return false }
        notice.waiting.remove(write)
        var skipped = false
        switch outcome {
        case nil, .accepted?, .merged?:
            notice.changed = true
            if let item = notice.items[write] { notice.queued.insert(item) }
        case .refused(let problem)?:
            if let reason = MarfaEngine.skipReason(problem.code) {
                notice.skips.skip(reason)
                skipped = true
            }
        case .conflicted?, .blocked?, .dead?:
            break
        }
        tellIfAnswered(notice)
        return skipped
    }

    private func tellIfAnswered(_ notice: SkipNotice) {
        guard !notice.isOpen, notice.waiting.isEmpty else { return }
        tellSkipped(notice.skips, didChange: notice.changed, failing: notice.failing)
        let answered = notice.answered
        notice.answered = nil
        answered?(notice)
    }
}
