import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// What a `[[link]]` written in one note names, as each library reads links.
@Suite struct FolderLinkResolutionTests {
    private func note(_ body: String, path: String? = nil, deleted: Bool = false) -> Note {
        Note(body: body, path: path, created: .now, deleted: deleted ? .now : nil)
    }

    private func library(_ notes: Note...) -> (NoteLibrary, reader: ItemID) {
        let reader = note("Reader\n\nSee the links.\n")
        return (NoteLibrary(notes: [reader] + notes, store: RecordingStore()), reader.id)
    }

    @Test func aLinkNamesTheNoteByTitleIgnoringCaseAndSpacingAround() {
        let plan = note("Plan\n\nThe plan.\n")
        let (library, reader) = library(plan)
        #expect(library.resolveLink("Plan", in: reader) == .resolved(plan.id))
        #expect(library.resolveLink("plan", in: reader) == .resolved(plan.id))
        #expect(library.resolveLink("  Plan ", in: reader) == .resolved(plan.id))
    }

    @Test func aLinkNamesTheNoteByPathWithOrWithoutItsExtension() {
        let quarterly = note("Quarterly planning\n", path: "Work/Quarterly.md")
        let (library, reader) = library(quarterly)
        #expect(library.resolveLink("Work/Quarterly", in: reader) == .resolved(quarterly.id))
        #expect(library.resolveLink("Work/Quarterly.md", in: reader) == .resolved(quarterly.id))
        #expect(library.resolveLink("Quarterly.md", in: reader) == .resolved(quarterly.id), "so does its file name")
        #expect(library.resolveLink("Work", in: reader) == .missing, "a folder is not a note")
    }

    @Test func aLinkNamesTheNoteByTheIdentityItsFileDeclares() {
        let identity = "33333333-3333-4333-8333-333333333333"
        let declared = note("---\nmarfa_id: \(identity)\n---\nPlan\n", path: "Plan.md")
        let (library, reader) = library(declared)
        #expect(library.resolveLink(identity, in: reader) == .resolved(declared.id))
    }

    @Test func aLinkToNoNoteIsMissingAndNothingIsMade() {
        let (library, reader) = library(note("Plan\n"))
        let before = library.items(in: .allNotes).map(\.id)
        #expect(library.resolveLink("Nowhere", in: reader) == .missing)
        #expect(library.resolveLink("", in: reader) == .missing)
        #expect(library.resolveLink("33333333-3333-4333-8333-333333333333", in: reader) == .missing)
        #expect(library.items(in: .allNotes).map(\.id) == before)
    }

    @Test func aNameHoldingAnAliasOrHeadingSeparatorNamesNothing() {
        let (library, reader) = library(note("Plan\n"))
        #expect(library.resolveLink("Plan#Soil", in: reader) == .missing)
        #expect(library.resolveLink("Plan|alias", in: reader) == .missing)
    }

    @Test func twoNotesWithOneTitleAreAmbiguousAndNeitherIsPicked() {
        let home = note("Garden\n", path: "Home/Garden.md")
        let work = note("Garden\n", path: "Work/Garden.md")
        let (library, reader) = library(home, work)
        guard case .ambiguous(let found) = library.resolveLink("Garden", in: reader) else {
            Issue.record("a name two notes go by names neither")
            return
        }
        #expect(Set(found) == [home.id, work.id])
        #expect(library.resolveLink("Home/Garden", in: reader) == .resolved(home.id), "their paths tell them apart")
    }

    @Test func aDeletedNoteIsNotNamed() {
        let (library, reader) = library(note("Plan\n", deleted: true))
        #expect(library.resolveLink("Plan", in: reader) == .missing)
    }

    @Test func aLinkFollowsANoteMadeOrRenamedWithoutReadingAgain() {
        let plan = note("Plan\n")
        let (library, reader) = library(plan)
        #expect(library.resolveLink("Later", in: reader) == .missing)
        let later = note("Later\n")
        library.notes.append(later)
        #expect(library.resolveLink("Later", in: reader) == .resolved(later.id))
        library.notes.removeAll { $0.id == plan.id }
        #expect(library.resolveLink("Plan", in: reader) == .missing)
    }
}

@MainActor
@Suite struct MarfaLinkResolutionTests {
    typealias F = LibraryFixture

    private func item(_ id: ItemID, _ title: String, state: ItemState = .active, links: [String: NoteReferenceResolution] = [:]) -> Item {
        var item = F.item(id, F.note, title, age: 1, state: state)
        item.linkTargets = Dictionary(uniqueKeysWithValues: links.map { (NoteLinks.nameKey($0.key), $0.value) })
        return item
    }

    private func loaded(_ items: [Item]) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source)
        source.send(.loaded(SourceSnapshot(items: items, catalogue: F.catalogue, places: [])))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private let reader = ItemID("reader")

    @Test func aTitleNamesTheOneNoteThatGoesByItWhenTheCopyHasNotBoundTheLinkYet() async throws {
        let plan = item(ItemID("plan"), "Plan")
        let (library, _) = try await loaded([item(reader, "Reader"), plan, item(ItemID("other"), "Other")])
        #expect(library.resolveLink("Plan", in: reader) == .resolved(plan.id))
        #expect(library.resolveLink("  plan ", in: reader) == .resolved(plan.id))
        #expect(library.resolveLink("Plan", in: ItemID("not-held")) == .resolved(plan.id), "a note the library lacks has bound nothing")
    }

    @Test func aTitleNobodyHereGoesByIsPendingNotMissingSinceTheServerMayHoldIt() async throws {
        let (library, _) = try await loaded([item(reader, "Reader")])
        #expect(library.resolveLink("Nowhere", in: reader) == .pending)
        #expect(library.resolveLink("", in: reader) == .missing)
    }

    @Test func twoNotesWithOneTitleAreAmbiguous() async throws {
        let (library, _) = try await loaded([item(reader, "Reader"), item(ItemID("a"), "Garden"), item(ItemID("b"), "garden")])
        #expect(library.resolveLink("Garden", in: reader) == .ambiguous([ItemID("a"), ItemID("b")]))
    }

    @Test func anIdentityNamesThatNoteWhateverOtherNotesAreTitled() async throws {
        let target = ItemID(UUID().uuidString.lowercased())
        let decoy = ItemID(UUID().uuidString.lowercased())
        let (library, _) = try await loaded([
            item(reader, "Reader"), item(target, "Target"), item(decoy, target.rawValue)])
        #expect(library.resolveLink(target.rawValue, in: reader) == .resolved(target))
        #expect(library.resolveLink(decoy.rawValue, in: reader) == .resolved(decoy))
    }

    @Test func anIdentityTheLibraryDoesNotHoldIsPendingUntilTheServerAnswers() async throws {
        let (library, _) = try await loaded([item(reader, "Reader")])
        #expect(library.resolveLink(UUID().uuidString.lowercased(), in: reader) == .pending)
    }

    @Test func aRenamedNoteKeepsTheLinkTheCopyBoundToIt() async throws {
        let renamed = item(ItemID("renamed"), "Plan v2")
        let reused = item(ItemID("reused"), "Plan")
        let bound = item(reader, "Reader", links: ["Plan": .resolved(renamed.id)])
        let (library, _) = try await loaded([bound, renamed, reused])
        #expect(library.resolveLink("Plan", in: reader) == .resolved(renamed.id), "the copy keeps the first note a name was bound to")
        #expect(library.resolveLink("Plan", in: renamed.id) == .resolved(reused.id), "from a note with no such link, the title names the new one")
    }

    @Test func whatTheCopyBoundALinkToIsTrustedOverTheTitlesHere() async throws {
        let plan = item(ItemID("plan"), "Plan")
        let gone = item(reader, "Reader", links: ["Plan": .missing, "Twin": .ambiguous([]), "Banned": .refused("forbidden")])
        let (library, _) = try await loaded([gone, plan, item(ItemID("twin"), "Twin")])
        #expect(library.resolveLink("Plan", in: reader) == .missing)
        #expect(library.resolveLink("Twin", in: reader) == .ambiguous([]))
        #expect(library.resolveLink("Banned", in: reader) == .refused("forbidden"))
    }

    @Test func aLinkTheCopyCouldNotLookUpYetIsReadAgainstTheTitlesHere() async throws {
        let plan = item(ItemID("plan"), "Plan")
        let waiting = item(reader, "Reader", links: ["Plan": .pending, "Later": .pending])
        let (library, _) = try await loaded([waiting, plan])
        #expect(library.resolveLink("Plan", in: reader) == .resolved(plan.id))
        #expect(library.resolveLink("Later", in: reader) == .pending)
    }

    @Test func aNoteInTheBinOrAFileIsNotNamed() async throws {
        var photo = item(ItemID("photo"), "Plan photo")
        photo.content = .file(.png, byteCount: 1)
        let binned = item(ItemID("binned"), "Old plan", state: .trashed)
        let bound = item(reader, "Reader", links: ["Bound": .resolved(ItemID("bound"))])
        let (library, _) = try await loaded([bound, photo, binned, item(ItemID("bound"), "Bound", state: .trashed)])
        #expect(library.resolveLink("Plan photo", in: reader) == .pending)
        #expect(library.resolveLink("Old plan", in: reader) == .pending)
        #expect(library.resolveLink(binned.id.rawValue, in: reader) == .pending, "not an identity, so a title nobody goes by")
        #expect(library.resolveLink("Bound", in: reader) == .missing, "bound to a note since deleted")
    }

    @Test func aBoundNoteTheLibraryDoesNotHoldIsNamedButNotHereYet() async throws {
        let bound = item(reader, "Reader", links: ["Elsewhere": .resolved(ItemID("elsewhere"))])
        let (library, _) = try await loaded([bound])
        #expect(library.resolveLink("Elsewhere", in: reader) == .pending)
    }

    @Test func titlesFollowNotesMadeRenamedAndDeleted() async throws {
        let plan = item(ItemID("plan"), "Plan")
        let (library, source) = try await loaded([item(reader, "Reader"), plan])
        var renamed = plan
        renamed.title = "Plan v2"
        renamed.version = ItemVersion(2)
        source.send(.upserted([renamed, item(ItemID("fresh"), "Fresh")]))
        #expect(await eventually { library.resolveLink("Fresh", in: reader) == .resolved(ItemID("fresh")) })
        #expect(library.resolveLink("Plan v2", in: reader) == .resolved(plan.id))
        #expect(library.resolveLink("Plan", in: reader) == .pending, "nobody goes by the old title")
        source.send(.removed([plan.id]))
        #expect(await eventually { library.resolveLink("Plan v2", in: reader) == .pending })
    }
}
