import Observation

/// Runs one Settings load at a time. A secondary failure leaves the rest of the page available.
@Observable @MainActor final class OwnerLoader {
    typealias Read = () async throws(OwnerFailure) -> Void

    @Observable @MainActor final class ReadStatus {
        fileprivate(set) var failure: OwnerFailure?
        fileprivate var isReading = false

        func clear() { failure = nil }
    }

    enum Secondary {
        case quiet(Read)
        case required(ReadStatus, Read)
    }

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var failure: OwnerFailure?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func load(
        in context: OwnerContext, waitForPrevious: Bool = false, primary: Read, secondary: [Secondary] = [],
        showBeforeFinishing: Bool = false, after: () async -> Void = {}
    ) async {
        while isLoading {
            guard waitForPrevious else { return }
            await withCheckedContinuation { waiters.append($0) }
            guard !Task.isCancelled else { return }
        }
        isLoading = true
        defer {
            isLoading = false
            let waiting = waiters
            waiters = []
            waiting.forEach { $0.resume() }
        }
        do {
            try await primary()
            failure = nil
        } catch {
            failure = error
            hasLoaded = true
            await context.learn(from: error)
            return
        }
        if showBeforeFinishing { hasLoaded = true }
        for read in secondary { await self.read(read, in: context) }
        await after()
        if !hasLoaded { hasLoaded = true }
    }

    func read(_ secondary: Secondary, in context: OwnerContext) async {
        switch secondary {
        case .quiet(let read):
            try? await read()
        case .required(let status, let read):
            guard !status.isReading else { return }
            status.isReading = true
            defer { status.isReading = false }
            do {
                try await read()
                status.clear()
            } catch {
                status.failure = error
                await context.learn(from: error)
            }
        }
    }

    func reset() {
        failure = nil
        hasLoaded = false
    }
}
