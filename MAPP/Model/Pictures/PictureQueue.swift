import Foundation

/// Lets only a few fetches run at once, overall and for each website, and holds the rest in the order they came.
/// A fetch that has to wait is not refused: it starts when a place is free.
///
/// A note with many pictures asks for all of them at once, and a website sees the person's Mac as one client, so
/// neither the Mac nor the website is sent a flood.
actor PictureQueue {
    nonisolated static let standardTotal = 4
    nonisolated static let standardPerHost = 2

    private let total: Int
    private let perHost: Int
    private var running = 0
    private var runningByHost: [String: Int] = [:]
    private var waiting: [(host: String, resume: CheckedContinuation<Void, Never>)] = []

    init(total: Int = PictureQueue.standardTotal, perHost: Int = PictureQueue.standardPerHost) {
        self.total = total
        self.perHost = perHost
    }

    /// Runs `work` when a place is free for a fetch from `host`. The work is never cancelled while it waits, since
    /// nothing cancels a fetch.
    func run<Result: Sendable>(host: String, _ work: @Sendable () async -> Result) async -> Result {
        if !canStart(host) {
            await withCheckedContinuation { waiting.append((host, $0)) }
        } else {
            start(host)
        }
        let result = await work()
        finish(host)
        return result
    }

    /// How many are waiting for a place.
    var waitingCount: Int { waiting.count }

    private func canStart(_ host: String) -> Bool {
        running < total && runningByHost[host, default: 0] < perHost
    }

    private func start(_ host: String) {
        running += 1
        runningByHost[host, default: 0] += 1
    }

    /// Frees the place and starts every waiting fetch that now fits, oldest first. One for a website that is full is
    /// passed over, so it never holds up a fetch from another.
    private func finish(_ host: String) {
        running -= 1
        runningByHost[host, default: 1] -= 1
        if runningByHost[host] == 0 { runningByHost[host] = nil }
        var index = 0
        while index < waiting.count, running < total {
            if canStart(waiting[index].host) {
                let next = waiting.remove(at: index)
                start(next.host)
                next.resume.resume()
            } else {
                index += 1
            }
        }
    }
}
