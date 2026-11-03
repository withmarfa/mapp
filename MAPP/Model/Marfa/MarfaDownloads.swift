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

struct MarfaDownloads: DownloadedFiles {
    private let copy: WorkingCopy

    init(copy: WorkingCopy) {
        self.copy = copy
    }

    func read() async throws -> DownloadedFileState {
        DownloadedFileState(try await copy.blobs.cache())
    }

    func setBudget(_ budget: DownloadBudget) async throws {
        _ = try await copy.blobs.setBudget(budget.marfa)
    }

    /// The package takes the files it can fetch again and leaves the budget alone. A cache it cannot read is an error
    /// to tell, never "nothing to remove".
    func removeDownloadedFiles() async throws {
        do {
            _ = try await copy.blobs.removeFetchedFiles()
        } catch let error as MarfaError {
            throw SourceFailure(kind: .failed, message: error.message)
        }
        await MarfaSource.removeKeptCopies()
    }
}
