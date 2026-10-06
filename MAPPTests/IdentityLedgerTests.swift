import Foundation
import Testing
@testable import MAPP

/// The matching alone, with no disk: what a reading of the folder finds, and the identifiers it gets.
struct IdentityLedgerTests {
    typealias Sighting = IdentityLedger.Sighting
    let start = Date(timeIntervalSince1970: 1_000_000)

    private func note(_ path: String, _ fileID: UInt64?) -> Sighting {
        Sighting(kind: .note, path: path, fileID: fileID)
    }

    @Test func eachItemGetsItsOwnIdentifierAndKeepsIt() {
        var ledger = IdentityLedger()
        let found = [note("One.md", 1), note("Two.md", 2), Sighting(kind: .file, path: "Picture.png", fileID: 3),
                     Sighting(kind: .folder, path: "Work", fileID: 4)]
        let first = ledger.identify(found, at: start)
        #expect(Set(first).count == 4)
        #expect(ledger.identify(found, at: start + 60) == first)
        #expect(ledger.entries.count == 4)
    }

    @Test func aRenamedFileIsKnownByItsIdentity() {
        var ledger = IdentityLedger()
        let id = ledger.identify([note("Plan.md", 7)], at: start)
        #expect(ledger.identify([note("Work/Plan B.md", 7)], at: start) == id)
        #expect(ledger.entries.map(\.path) == ["Work/Plan B.md"])
    }

    @Test func filesThatSwapNamesKeepTheirOwnIdentifiers() {
        var ledger = IdentityLedger()
        let ids = ledger.identify([note("A.md", 1), note("B.md", 2)], at: start)
        #expect(ledger.identify([note("A.md", 2), note("B.md", 1)], at: start) == [ids[1], ids[0]])
    }

    @Test func aNewFileAtARenamedFilesOldPathIsNew() {
        var ledger = IdentityLedger()
        let id = ledger.identify([note("Plan.md", 1)], at: start)[0]
        let after = ledger.identify([note("Plan.md", 2), note("Old Plan.md", 1)], at: start)
        #expect(after[1] == id)
        #expect(after[0] != id)
    }

    @Test func aSafeSaveThatChangesTheFileIdentityKeepsTheIdentifier() {
        var ledger = IdentityLedger()
        let id = ledger.identify([note("Plan.md", 1)], at: start)
        #expect(ledger.identify([note("Plan.md", 2)], at: start) == id)
        #expect(ledger.entries.first?.fileID == 2, "the new identity is remembered, so a later rename is followed")
        #expect(ledger.identify([note("Renamed.md", 2)], at: start) == id)
    }

    /// A file deleted and written again at its path is indistinguishable from a save that replaces the file
    /// whole, which many editors make, so it stays the same item.
    @Test func aFileDeletedAndMadeAgainAtItsPathKeepsTheIdentifier() {
        var ledger = IdentityLedger()
        let id = ledger.identify([note("Plan.md", 1)], at: start)
        #expect(ledger.identify([], at: start + 1).isEmpty)
        #expect(ledger.identify([note("Plan.md", 9)], at: start + 2) == id)
    }

    @Test func aCopyIsNew() {
        var ledger = IdentityLedger()
        let id = ledger.identify([note("Plan.md", 1)], at: start)[0]
        let after = ledger.identify([note("Plan.md", 1), note("Plan copy.md", 2)], at: start)
        #expect(after[0] == id)
        #expect(after[1] != id)
    }

    @Test func hardLinksKeepTheirOwnIdentifiers() {
        var ledger = IdentityLedger()
        let ids = ledger.identify([note("A.md", 1), note("B.md", 1)], at: start)
        #expect(ids[0] != ids[1])
        #expect(ledger.identify([note("B.md", 1), note("A.md", 1)], at: start) == [ids[1], ids[0]])
    }

    @Test func withoutFileIdentitiesItemsAreKnownByPath() {
        var ledger = IdentityLedger()
        let ids = ledger.identify([note("A.md", nil), note("B.md", nil)], at: start)
        #expect(ledger.identify([note("B.md", nil), note("A.md", nil)], at: start) == [ids[1], ids[0]])
    }

    @Test func aFolderAndAnItemNeverShareAnEntry() {
        var ledger = IdentityLedger()
        let folder = ledger.identify([Sighting(kind: .folder, path: "Work", fileID: 1)], at: start)[0]
        let item = ledger.identify([Sighting(kind: .file, path: "Work", fileID: 1)], at: start)[0]
        #expect(item != folder)
    }

    @Test func aNoteThatBecomesAFileKeepsItsIdentifier() {
        var ledger = IdentityLedger()
        let id = ledger.identify([note("Plan.md", 1)], at: start)
        #expect(ledger.identify([Sighting(kind: .file, path: "Plan.txt", fileID: 1)], at: start) == id)
    }

    @Test func aTrashedNoteIsKnownByItsPlaceInTheBinAndComesBackItself() {
        var ledger = IdentityLedger()
        let id = ledger.identify([note("Work/Plan.md", 1)], at: start)
        let binID = UUID()
        ledger.trash("Work/Plan.md", binID: binID)
        #expect(ledger.identify([Sighting(kind: .note, binID: binID)], at: start) == id)
        ledger.restore(binID, to: "Plan.md", fileID: 1)
        #expect(ledger.identify([note("Plan.md", 1)], at: start) == id)
        #expect(ledger.entries.count == 1)
    }

    @Test func aFolderMovedTakesWhatIsInItAlong() {
        var ledger = IdentityLedger()
        let ids = ledger.identify([Sighting(kind: .folder, path: "Work", fileID: nil), note("Work/Deep/Plan.md", nil), note("Workshop.md", nil)], at: start)
        ledger.move(from: "Work", to: "Office", isFolder: true)
        let after = ledger.identify([Sighting(kind: .folder, path: "Office", fileID: nil), note("Office/Deep/Plan.md", nil), note("Workshop.md", nil)], at: start)
        #expect(after == ids)
    }

    @Test func whatTheAppMakesKeepsTheIdentifierItWasGiven() {
        var ledger = IdentityLedger()
        let id = UUID()
        _ = ledger.identify([note("Plan.md", 1)], at: start)
        _ = ledger.identify([], at: start + 1)
        ledger.record(id, kind: .note, path: "Plan.md", fileID: 5)
        #expect(ledger.entries.count == 1, "what was gone from the place gives way")
        #expect(ledger.identify([note("Plan.md", 5)], at: start + 2) == [id])
    }

    @Test func somethingGoneIsRememberedForAWhileThenForgotten() {
        var ledger = IdentityLedger()
        let id = ledger.identify([note("Plan.md", 1)], at: start)
        _ = ledger.identify([], at: start)
        #expect(ledger.entries.first?.missing == start)
        _ = ledger.identify([], at: start + IdentityLedger.retention - 1)
        #expect(ledger.entries.first?.missing == start, "when it went is not moved on")
        #expect(ledger.identify([note("Moved back.md", 1)], at: start + IdentityLedger.retention - 1) == id)
        #expect(ledger.entries.first?.missing == nil)
        _ = ledger.identify([], at: start + IdentityLedger.retention)
        _ = ledger.identify([], at: start + 2 * IdentityLedger.retention)
        #expect(ledger.entries.isEmpty)
    }

    @Test func purgedNotesAreForgotten() {
        var ledger = IdentityLedger()
        _ = ledger.identify([note("A.md", 1), note("B.md", 2)], at: start)
        let gone = UUID()
        ledger.trash("A.md", binID: gone)
        ledger.purge([gone])
        #expect(ledger.entries.map(\.path) == ["B.md"])
    }

    @Test func theLedgerReadsBackAsItWasWritten() throws {
        var ledger = IdentityLedger()
        _ = ledger.identify([note("A.md", UInt64.max), Sighting(kind: .folder, path: "Work", fileID: 2), Sighting(kind: .note, binID: UUID())], at: start)
        _ = ledger.identify([note("A.md", UInt64.max)], at: start + 1)
        let read = try JSONDecoder().decode(IdentityLedger.self, from: JSONEncoder().encode(ledger))
        #expect(read == ledger)
    }
}
