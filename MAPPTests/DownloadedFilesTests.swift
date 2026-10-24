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

    @Test(arguments: [DownloadBudget.automatic, .bytes(12345), .keepAll], [false, true])
    func closingDuringRemovalKeepsTheSavedBudget(_ budget: DownloadBudget, agreeing: Bool) async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = directory.appending(path: "copy.sqlite")
        let copy = try await WorkingCopy.open(store: store, fileBudget: budget.marfa)
        let source = MarfaSource(copy: copy, connection: try MarfaConnection(address: "https://example.test"))
        let files = try #require(source.downloadedFiles as? MarfaDownloads)
        let (entered, enteredContinuation) = AsyncStream<Void>.makeStream()
        let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
        defer { releaseContinuation.finish() }
        await files.whenRemoving {
            enteredContinuation.finish()
            for await _ in release { }
        }
        let removal = Task { try await files.removeDownloadedFiles() }
        for await _ in entered { }
        #expect(try await copy.blobs.cache().setting == .bytes(bytes: 0))
        await #expect(throws: SourceFailure.self) { try await source.tryKey("unused") }
        let closing = Task {
            if agreeing { #expect(await source.close(agreeing: nil) == .closed) }
            else { await source.close() }
        }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while !(await files.stopped), clock.now < deadline { await Task.yield() }
        #expect(await files.stopped)
        // Close has reached the download barrier, but the copy must still accept the restore.
        #expect(try await copy.blobs.cache().setting == .bytes(bytes: 0))
        await #expect(throws: MarfaError.self) { try await files.setBudget(.keepAll) }
        removal.cancel()
        releaseContinuation.finish()
        try await removal.value
        await closing.value
        let reopened = try await WorkingCopy.open(store: store)
        #expect(try await reopened.blobs.cache().setting == budget.marfa)
        await reopened.close()
    }
}
