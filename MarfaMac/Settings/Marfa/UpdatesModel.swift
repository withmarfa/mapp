import Foundation
import Marfa
import Observation

/// The Updates page: the release the server runs, whether a newer one is ready, Check for Updates and Update, the steps an
/// update goes through while it runs, and how the last one ended. Starting an update needs `instance.maintain`; the server
/// restarts to take it, so the page follows it, treating a server that does not answer for a while as restarting. An update
/// the server put back is told with its own words and offers Try Again, never a second Update.
@Observable @MainActor final class UpdatesModel {
    private let context: OwnerContext
    /// How long to wait between reads while an update runs, and how many unanswered reads to wait through before giving up.
    private let pause: Duration
    private let patience: Int

    private(set) var status: UpdateStatus?
    private let loader = OwnerLoader()
    var failure: OwnerFailure? { loader.failure }
    private let settingsRead = OwnerLoader.ReadStatus()
    var settingsFailure: OwnerFailure? { settingsRead.failure }
    var canChangeSettings: Bool { context.grants().contains(.configManage) }
    var hasLoaded: Bool { loader.hasLoaded }
    private(set) var isChecking = false
    private(set) var isStarting = false
    /// Whether the server stopped answering while an update ran, which is how it restarts.
    private(set) var isRestarting = false
    /// Why the last check, start or switch was refused, in one line, until the next.
    private(set) var error: OwnerFailure?
    /// Whether the update was lost track of: the server did not come back in the time the app waits. Until a read of the status
    /// shows where it stands, the server may still be updating, so Update is not offered again.
    private(set) var lostTrack = false
    /// The one task that follows an update, held so it ends with the page.
    private var follower: Task<Void, Never>?
    private var stopGeneration = 0
    private(set) var isSwitching = false
    /// Where Check Automatically is held, which needs `config.manage` to change.
    private(set) var settings: UpkeepSettings?

    init(context: OwnerContext, pause: Duration = .seconds(2), patience: Int = 90) {
        self.context = context
        self.pause = pause
        self.patience = patience
    }

    var isUpdating: Bool { status?.progress != nil || isStarting }

    /// What the progress list shows: each stage with where it stands.
    enum Standing: Hashable { case done, now, next }

    func standing(of stage: UpdateStage) -> Standing {
        let current = isRestarting ? UpdateStage.restarting : (status?.progress?.stage ?? .fetching)
        return stage.rawValue < current.rawValue ? .done : (stage == current ? .now : .next)
    }

    /// The update that did not take, where the last one was put back or failed and its release is not the one running.
    var undone: UpdateOutcome? {
        guard let last = status?.last, last.result != .succeeded, last.release != status?.running else { return nil }
        return last
    }

    /// The release the Marfa row calls ready. An update the server put back is offered through Try Again alone, so the row
    /// does not offer it a second time.
    var ready: UpdateRelease? {
        guard let status, status.available, undone == nil, !lostTrack else { return nil }
        return status.latest
    }

    func load() async {
        let generation = stopGeneration
        await loader.load(in: context, waitForPrevious: true, primary: { () throws(OwnerFailure) in
            guard generation == stopGeneration, !Task.isCancelled else { return }
            do throws(OwnerFailure) {
                let reading = try await context.calls.updateStatus()
                guard generation == stopGeneration, !Task.isCancelled else { return }
                status = reading
                lostTrack = false
            } catch {
                guard generation == stopGeneration, !Task.isCancelled else { return }
                throw UpkeepWording.owned(error)
            }
        }, showBeforeFinishing: true, after: {
            guard generation == stopGeneration, !Task.isCancelled else { return }
            if status?.progress != nil { await follow() }
            guard generation == stopGeneration, !Task.isCancelled else { return }
            await loader.read(.required(settingsRead) { [self] () throws(OwnerFailure) in
                guard canChangeSettings else {
                    settings = nil
                    return
                }
                do throws(OwnerFailure) {
                    let reading = try await context.calls.upkeepSettings()
                    guard generation == stopGeneration, !Task.isCancelled, canChangeSettings else { return }
                    settings = reading
                } catch {
                    guard generation == stopGeneration, !Task.isCancelled else { return }
                    throw error
                }
            }, in: context)
        })
    }

    // MARK: Check and update

    /// Whether Check for Updates can be pressed: the server runs no `release-check` job while Check Automatically is off, and it
    /// answers 404 then.
    var canCheck: Bool {
        guard let status else { return false }
        return status.checksAutomatically && !isChecking && !isUpdating
    }

    /// Whether the sign-in lacks `instance.maintain`, which Update and Check for Updates need: the page offers Allow More… first.
    var needsMaintain: Bool { !context.grants().contains(.instanceMaintain) }

    func checkForUpdates() async {
        guard canCheck else { return }
        isChecking = true
        error = nil
        defer { isChecking = false }
        do {
            status = try await context.calls.checkForUpdates()
            lostTrack = false
        } catch {
            let error = UpkeepWording.owned(error)
            self.error = error
            await context.learn(from: error)
        }
    }

    /// Whether Update can be pressed: a newer release is ready, the server can swap its own programs and nothing is running.
    var canUpdate: Bool {
        guard let status else { return false }
        return status.available && status.updatesItself && !isUpdating && !isChecking && !lostTrack
    }

    func update() async {
        guard canUpdate, !Task.isCancelled else { return }
        let generation = stopGeneration
        isStarting = true
        error = nil
        lostTrack = false
        do {
            status = try await context.calls.startUpdate()
        } catch {
            let error = UpkeepWording.owned(error)
            isStarting = false
            self.error = error
            await context.learn(from: error)
            return
        }
        isStarting = false
        guard generation == stopGeneration, !Task.isCancelled else { return }
        await follow()
    }

    var isFollowing: Bool { follower != nil }

    /// Follows the update to its end, as the one follower there is: a second call waits for the first.
    private func follow() async {
        guard !Task.isCancelled else { return }
        if let follower {
            await follower.value
            return
        }
        let task = Task { await read() }
        follower = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if follower == task {
            follower = nil
            isRestarting = false
        }
    }

    /// Ends the follower, as when the page goes. The update itself carries on at the server.
    func stop() {
        stopGeneration += 1
        follower?.cancel()
        follower = nil
        isRestarting = false
    }

    /// Reads the update until it ends. The server ends itself to start the new release, so a read that fails while it runs is
    /// the restart, not a fault; the app waits `patience` reads for it and then says it lost track. The server answers a second
    /// start with the update that runs, in the same 202, so a start is followed whichever it was.
    private func read() async {
        var unanswered = 0
        while status?.progress != nil {
            try? await Task.sleep(for: pause)
            if Task.isCancelled { return }
            do {
                let reading = try await context.calls.updateStatus()
                if Task.isCancelled { return }
                status = reading
                isRestarting = false
                unanswered = 0
            } catch {
                if Task.isCancelled { return }
                let error = UpkeepWording.owned(error)
                if case .notPermitted = error {
                    self.error = error
                    await context.learn(from: error)
                    return
                }
                isRestarting = true
                unanswered += 1
                if unanswered >= patience {
                    lostTrack = true
                    isRestarting = false
                    status?.progress = nil
                    return
                }
            }
        }
        isRestarting = false
    }

    // MARK: Check Automatically

    func setChecksAutomatically(_ on: Bool) async {
        guard canChangeSettings, settingsFailure == nil, let settings, !isSwitching, settings.checksForUpdates != on else { return }
        isSwitching = true
        error = nil
        defer { isSwitching = false }
        do {
            self.settings = try await context.calls.change(settings, .init(checksForUpdates: on))
            status?.checksAutomatically = on
        } catch {
            let error = UpkeepWording.owned(error)
            self.error = error
            await context.learn(from: error)
        }
    }
}
