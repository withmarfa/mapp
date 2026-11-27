import Foundation
import Marfa
import Observation

/// The Housekeeping page: the jobs the server runs by itself, with how often, when each last ran and how that went, and the
/// clock hold. While the server's clock reads more than 7 days past the time it last trusted, the jobs that delete wait;
/// Confirm Date… tells the server the clock is right (`instance.maintain`), after the owner agrees.
@Observable @MainActor final class HousekeepingModel {
    private let context: OwnerContext

    private(set) var jobs: [HousekeepingJob] = []
    private let loader = OwnerLoader()
    var failure: OwnerFailure? { loader.failure }
    var hasLoaded: Bool { loader.hasLoaded }
    /// The date the server's clock reads, which the owner is asked to confirm; set while the alert is up.
    private(set) var confirming: Date?
    private(set) var isConfirming = false
    private(set) var isAsking = false
    /// Why the date was not confirmed, in the problem row's place, until the next try.
    private(set) var confirmError: OwnerFailure?

    init(context: OwnerContext) {
        self.context = context
    }

    func load() async {
        await loader.load(in: context, primary: { () throws(OwnerFailure) in
            do throws(OwnerFailure) {
                jobs = try await context.calls.housekeepingJobs()
            } catch {
                throw UpkeepWording.owned(error)
            }
        })
    }

    /// Every job the server reports, ordered by its displayed name.
    var listed: [HousekeepingJob] {
        jobs.sorted { UpkeepWording.jobTitle($0.name).localizedStandardCompare(UpkeepWording.jobTitle($1.name)) == .orderedAscending }
    }

    // MARK: The clock

    /// What the server said when the date was confirmed, where it was not the date the owner was shown.
    private(set) var confirmedInstead: (shown: Date, confirmed: Date)?

    /// Reads the hold again, so the owner is asked about the date the server's clock reads now, and asks. Nothing is asked once the
    /// hold has gone.
    func askToConfirm(health: ServerHealthModel) async {
        guard !isConfirming, !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        await health.load()
        askToConfirm(clock: health.health?.housekeeping?.hold?.clockAt)
    }

    func askToConfirm(clock: Date?) {
        guard let clock, !isConfirming else { return }
        confirmError = nil
        confirmedInstead = nil
        confirming = clock
    }

    func cancelConfirming() {
        guard !isConfirming else { return }
        confirming = nil
    }

    /// Confirms `date`, the one the owner was shown and agreed to, then reads the jobs and the health again so the hold goes. The
    /// alert's own binding clears `confirming` before this runs, so the date is passed in. A server that took another date says so.
    func confirm(date: Date, health: ServerHealthModel) async {
        guard !isConfirming else { return }
        isConfirming = true
        confirmError = nil
        confirmedInstead = nil
        confirming = nil
        defer { isConfirming = false }
        do {
            if let taken = try await context.calls.confirmClock(), !Calendar.current.isDate(taken, inSameDayAs: date) {
                confirmedInstead = (date, taken)
            }
        } catch {
            let error = UpkeepWording.owned(error)
            confirmError = error
            await context.learn(from: error)
            return
        }
        await health.load()
        await load()
    }
}
