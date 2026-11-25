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
        var waiting: Set<WriteID> = []
        var isOpen = true

        init(failing: String) {
            self.failing = failing
        }
    }

    /// Runs `command`, gathering what it and the engine skip into one notice titled `failing` where nothing changed.
    func gatheringSkips(failing title: String, _ command: () -> Void) {
        let outer = gathering
        let notice = SkipNotice(failing: title)
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

    /// The source took `write` for the command being gathered.
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
    }
}
