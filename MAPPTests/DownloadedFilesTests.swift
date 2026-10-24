import Foundation
import Marfa
import Testing
@testable import MAPP

@Suite struct DownloadedFilesTests {
    @Test func budgetRoundTripsWithoutRounding() {
        for budget in [DownloadBudget.automatic, .bytes(12345), .keepAll] {
            #expect(DownloadBudget(budget.marfa) == budget)
        }
    }

    @Test func unknownCountsAreNotShownAsZero() {
        let cache = FileCache(setting: .default, budget: nil, held: nil, heldUnreadable: "unreadable",
                              volumeUnreadable: true, backupMarkFailure: nil, attachments: nil)
        let files = DownloadedFileState(cache)
        #expect(files.bytes == nil)
        #expect(files.attachments == nil)
        #expect(files.budget == .automatic)
    }

    @Test func everyMissingAttachmentReasonHasUsefulWords() {
        for reason in NotHeldReason.allCases {
            let missing = MissingAttachments(reason: reason, count: 3)
            #expect(!DownloadWording.reason(missing).isEmpty)
            #expect(DownloadWording.reason(missing).contains("3"))
        }
        #expect(DownloadWording.reason(MissingAttachments(reason: .noRoom, count: 3)).contains("space"))
    }

    @Test func removalRestoresTheChosenBudgetAndKeepsUploads() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copy = try await WorkingCopy.open(store: directory.appending(path: "copy.sqlite"), fileBudget: .keepAll)
        let file = directory.appending(path: "upload.txt")
        try Data("Waiting to upload".utf8).write(to: file)
        let upload = try await copy.blobs.put(file: file)
        let queued = try await copy.queue.all()
        let files = MarfaDownloads(copy: copy)
        try await files.removeDownloadedFiles()
        #expect(try await files.read().budget == .keepAll)
        #expect(try await copy.queue.all() == queued)
        let hash = try #require(upload.blob)
        let text = try await copy.blobs.withFile(hash) { try String(contentsOf: $0, encoding: .utf8) }
        #expect(text == "Waiting to upload")
        try await files.setBudget(.bytes(1))
        let largerThanBudget = try await copy.blobs.withFile(hash) { try Data(contentsOf: $0) }
        #expect(largerThanBudget == Data("Waiting to upload".utf8))
        await copy.close()
    }

    @Test func theChosenLimitSurvivesReopeningAndCanReturnToAutomatic() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = directory.appending(path: "copy.sqlite")
        let first = try await WorkingCopy.open(store: store)
        let files = MarfaDownloads(copy: first)
        #expect(try await files.read().budget == .automatic)
        try await files.setBudget(.bytes(12345))
        await first.close()
        let reopened = try await WorkingCopy.open(store: store)
        let again = MarfaDownloads(copy: reopened)
        #expect(try await again.read().budget == .bytes(12345))
        try await again.setBudget(.automatic)
        #expect(try await again.read().budget == .automatic)
        await reopened.close()
    }
}
