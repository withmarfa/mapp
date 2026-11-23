import Foundation

nonisolated enum DownloadBudget: Hashable, Sendable {
    case automatic, bytes(UInt64), keepAll
}

nonisolated struct MissingAttachments: Hashable, Sendable {
    enum Reason: Hashable, Sendable { case waiting, space, offline, later, absent, failed, missingItem }
    var reason: Reason
    var count: UInt64
}

nonisolated struct DownloadedFileState: Hashable, Sendable {
    struct Attachments: Hashable, Sendable {
        var held: UInt64
        var missing: UInt64
        var reasons: [MissingAttachments]
    }
    var budget: DownloadBudget
    var limit: UInt64?
    var bytes: UInt64?
    var attachments: Attachments?
}

nonisolated protocol DownloadedFiles: Sendable {
    func read() async throws -> DownloadedFileState
    func setBudget(_ budget: DownloadBudget) async throws
    func removeDownloadedFiles() async throws
}

nonisolated enum DownloadWording {
    /// The line under "Attachments Not Yet Offline": the one reason as a sentence, "Waiting to download.", or, where
    /// there are several, each with its count. Nil where the copy has not said why.
    static func line(_ reasons: [MissingAttachments]) -> String? {
        guard let only = reasons.first else { return nil }
        guard reasons.count > 1 else { return sentence(only.reason) }
        return reasons.map(reason).joined(separator: ". ") + "."
    }

    static func sentence(_ reason: MissingAttachments.Reason) -> String {
        switch reason {
        case .waiting: String(localized: "Waiting to download.")
        case .space: String(localized: "Needs more disk space.")
        case .offline: String(localized: "Waiting for a connection.")
        case .later: String(localized: "Waiting for the server.")
        case .absent: String(localized: "Unavailable on the server.")
        case .failed: String(localized: "Couldn’t be downloaded.")
        case .missingItem: String(localized: "Waiting for file details.")
        }
    }

    static func reason(_ missing: MissingAttachments) -> String {
        let count = missing.count
        switch missing.reason {
        case .waiting: return String(localized: "\(count) waiting to download")
        case .space: return String(localized: "\(count) need more disk space")
        case .offline: return String(localized: "\(count) waiting for a connection")
        case .later: return String(localized: "\(count) waiting for the server")
        case .absent: return String(localized: "\(count) unavailable on the server")
        case .failed: return String(localized: "\(count) couldn’t be downloaded")
        case .missingItem: return String(localized: "\(count) waiting for file details")
        }
    }
}
