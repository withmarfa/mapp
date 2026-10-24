import Foundation
import Testing
@testable import MAPP

@Suite struct MarfaKeptFileTests {
    private func leasedFile(holding text: String) throws -> URL {
        let file = URL.temporaryDirectory.appending(path: "leased-\(UUID().uuidString)")
        try Data(text.utf8).write(to: file)
        return file
    }

    @Test func aKeptCopyOutlastsTheLeasedFile() throws {
        let hash = "sha256:\(UUID().uuidString)"
        let leased = try leasedFile(holding: "bytes")
        let kept = try MarfaSource.keptCopy(of: leased, named: hash)
        defer { try? FileManager.default.removeItem(at: kept) }

        try FileManager.default.removeItem(at: leased)

        #expect(try String(contentsOf: kept, encoding: .utf8) == "bytes")
        #expect(kept.lastPathComponent == hash)
    }

    @Test func aHashAlreadyKeptIsAnsweredWithoutCopyingAgain() throws {
        let hash = "sha256:\(UUID().uuidString)"
        let first = try leasedFile(holding: "first")
        let kept = try MarfaSource.keptCopy(of: first, named: hash)
        defer { try? FileManager.default.removeItem(at: kept) }

        let again = try MarfaSource.keptCopy(of: try leasedFile(holding: "second"), named: hash)

        #expect(again == kept)
        #expect(try String(contentsOf: again, encoding: .utf8) == "first")
    }

    @Test func aMissingLeasedFileThrowsAndLeavesNothingKept() throws {
        let hash = "sha256:\(UUID().uuidString)"
        let missing = URL.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)")

        #expect(throws: (any Error).self) { try MarfaSource.keptCopy(of: missing, named: hash) }

        let directory = URL.temporaryDirectory.appending(path: "MAPP Files")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(!names.contains { $0.hasPrefix(hash) })
    }
}
