import Foundation
import Marfa

nonisolated extension DownloadBudget {
    init(_ budget: FileBudget) {
        self = switch budget {
        case .default: .automatic
        case .bytes(let bytes): .bytes(bytes)
        case .keepAll: .keepAll
        }
    }

    var marfa: FileBudget {
        switch self {
        case .automatic: .default
        case .bytes(let bytes): .bytes(bytes: bytes)
        case .keepAll: .keepAll
        }
    }
}

nonisolated extension MissingAttachments {
    init(reason: NotHeldReason, count: UInt64) {
        self.count = count
        self.reason = switch reason {
        case .notFetched: .waiting
        case .noRoom: .space
        case .unreachable: .offline
        case .rateLimited: .later
        case .absent: .absent
        case .failed: .failed
        case .notInCopy: .missingItem
        }
    }
}

nonisolated extension DownloadedFileState {
    init(_ cache: FileCache) {
        budget = DownloadBudget(cache.setting)
        limit = cache.budget
        bytes = cache.held
        attachments = cache.attachments.map {
            Attachments(held: $0.held, missing: $0.notHeld,
                        reasons: $0.notHeldByReason.map { MissingAttachments(reason: $0.reason, count: $0.attachments) })
        }
    }
}

actor MarfaDownloads: DownloadedFiles {
    private let copy: WorkingCopy
    private var changing = false
    private(set) var stopped = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    #if DEBUG
    private var removing: (@Sendable () async -> Void)?

    func whenRemoving(_ hook: (@Sendable () async -> Void)?) { removing = hook }
    #endif

    init(copy: WorkingCopy) { self.copy = copy }

    func read() async throws -> DownloadedFileState {
        DownloadedFileState(try await copy.blobs.cache())
    }

    func setBudget(_ budget: DownloadBudget) async throws {
        guard !stopped else { throw MarfaError.closed(message: MarfaEngine.closedLibrary) }
        guard !changing else { throw Self.busy }
        changing = true
        defer { finished() }
        _ = try await copy.blobs.setBudget(budget.marfa)
    }

    func removeDownloadedFiles() async throws {
        guard !stopped else { throw MarfaError.closed(message: MarfaEngine.closedLibrary) }
        guard !changing else { throw Self.busy }
        changing = true
        defer { finished() }
        let setting = try await copy.blobs.cache().setting
        // A zero budget trims only expendable downloads; attachments, uploads and leased files stay.
        // Restore even if the trim throws after persisting the temporary setting.
        do {
            _ = try await copy.blobs.setBudget(.bytes(bytes: 0))
            #if DEBUG
            await removing?()
            #endif
        } catch {
            _ = try await copy.blobs.setBudget(setting)
            throw error
        }
        _ = try await copy.blobs.setBudget(setting)
    }

    /// Replacing the key also drops the core, so it cannot interrupt a budget restore.
    func useKey(_ key: String) async throws {
        guard !stopped else { throw MarfaError.closed(message: MarfaEngine.closedLibrary) }
        guard !changing else { throw Self.busy }
        changing = true
        defer { finished() }
        try await copy.useKey(key)
    }

    /// The package has no trim-to-zero call that leaves the preference alone. Closing must wait for its restore.
    func stop() async {
        stopped = true
        if changing { await withCheckedContinuation { waiting.append($0) } }
    }

    private func finished() {
        changing = false
        let done = waiting
        waiting = []
        for waiter in done { waiter.resume() }
    }

    private static var busy: SourceFailure {
        SourceFailure(kind: .failed, message: String(localized: "Wait for the current download change to finish."))
    }
}
