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
        #expect(library.resolveLink(NoteLink(name: "Plan"), in: reader) == .resolved(plan.id))
        #expect(library.resolveLink(NoteLink(name: "plan"), in: reader) == .resolved(plan.id))
        #expect(library.resolveLink(NoteLink(name: "  Plan "), in: reader) == .resolved(plan.id))
    }

    @Test func aLinkNamesTheNoteByPathWithOrWithoutItsExtension() {
        let quarterly = note("Quarterly planning\n", path: "Work/Quarterly.md")
        let (library, reader) = library(quarterly)
        #expect(library.resolveLink(NoteLink(name: "Work/Quarterly"), in: reader) == .resolved(quarterly.id))
        #expect(library.resolveLink(NoteLink(name: "Work/Quarterly.md"), in: reader) == .resolved(quarterly.id))
        #expect(library.resolveLink(NoteLink(name: "Quarterly.md"), in: reader) == .resolved(quarterly.id), "so does its file name")
        #expect(library.resolveLink(NoteLink(name: "Work"), in: reader) == .missing, "a folder is not a note")
    }

    @Test func aLinkNamesTheNoteByTheIdentityItsFileDeclares() {
        let identity = "33333333-3333-4333-8333-333333333333"
        let declared = note("---\nmarfa_id: \(identity)\n---\nPlan\n", path: "Plan.md")
        let (library, reader) = library(declared)
        #expect(library.resolveLink(NoteLink(name: identity), in: reader) == .resolved(declared.id))
    }

    @Test func aLinkToNoNoteIsMissingAndNothingIsMade() {
        let (library, reader) = library(note("Plan\n"))
        let before = library.items(in: .allNotes).map(\.id)
        #expect(library.resolveLink(NoteLink(name: "Nowhere"), in: reader) == .missing)
        #expect(library.resolveLink(NoteLink(name: ""), in: reader) == .missing)
        #expect(library.resolveLink(NoteLink(name: "33333333-3333-4333-8333-333333333333"), in: reader) == .missing)
        #expect(library.items(in: .allNotes).map(\.id) == before)
    }

    @Test func aNameHoldingAnAliasOrHeadingSeparatorNamesNothing() {
        let (library, reader) = library(note("Plan\n"))
        #expect(library.resolveLink(NoteLink(name: "Plan#Soil"), in: reader) == .missing)
        #expect(library.resolveLink(NoteLink(name: "Plan|alias"), in: reader) == .missing)
    }

    @Test func twoNotesWithOneTitleAreAmbiguousAndNeitherIsPicked() {
        let home = note("Garden\n", path: "Home/Garden.md")
        let work = note("Garden\n", path: "Work/Garden.md")
        let (library, reader) = library(home, work)
        guard case .ambiguous(let found) = library.resolveLink(NoteLink(name: "Garden"), in: reader) else {
            Issue.record("a name two notes go by names neither")
            return
        }
        #expect(Set(found) == [home.id, work.id])
        #expect(library.resolveLink(NoteLink(name: "Home/Garden"), in: reader) == .resolved(home.id), "their paths tell them apart")
    }

    @Test func aDeletedNoteIsNotNamed() {
        let (library, reader) = library(note("Plan\n", deleted: true))
        #expect(library.resolveLink(NoteLink(name: "Plan"), in: reader) == .missing)
    }

    @Test func aLinkFollowsANoteMadeOrRenamedWithoutReadingAgain() {
        let plan = note("Plan\n")
        let (library, reader) = library(plan)
        #expect(library.resolveLink(NoteLink(name: "Later"), in: reader) == .missing)
        let later = note("Later\n")
        library.notes.append(later)
        #expect(library.resolveLink(NoteLink(name: "Later"), in: reader) == .resolved(later.id))
        library.notes.removeAll { $0.id == plan.id }
        #expect(library.resolveLink(NoteLink(name: "Plan"), in: reader) == .missing)
    }
}

@MainActor
@Suite struct MarfaLinkResolutionTests {
    typealias F = LibraryFixture

    private func item(_ id: ItemID, _ title: String, state: ItemState = .active, links: [BoundLink] = []) -> Item {
        var item = F.item(id, F.note, title, age: 1, state: state)
        item.boundLinks = links
        return item
    }

    private func bound(_ raw: String, _ resolution: NoteReferenceResolution) -> BoundLink {
        BoundLink(link: NoteLink(reading: raw), resolution: resolution)
    }

    private func loaded(_ items: [Item]) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source)
        source.send(.loaded(SourceSnapshot(items: items, catalogue: F.catalogue, places: [])))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private let reader = ItemID("reader")

    @Test func aLinkTheCopyHasNotBoundIsPendingNeverGuessedFromTheTitlesHere() async throws {
        let plan = item(ItemID("plan"), "Plan")
        let (library, _) = try await loaded([item(reader, "Reader"), plan, item(ItemID("other"), "Other")])
        // The server may hold another note with that title; only the copy's binding says which one the link names.
        #expect(library.resolveLink(NoteLink(name: "Plan"), in: reader) == .pending)
        #expect(library.resolveLink(NoteLink(name: "Plan"), in: ItemID("not-held")) == .pending)
        #expect(library.resolveLink(NoteLink(name: "Nowhere"), in: reader) == .pending)
        #expect(library.resolveLink(NoteLink(name: ""), in: reader) == .missing)
    }

    @Test func aLinkTheCopyBoundOpensWhatItBoundItTo() async throws {
        let plan = item(ItemID("plan"), "Plan")
        let source = item(reader, "Reader", links: [bound("Plan", .resolved(plan.id))])
        let (library, _) = try await loaded([source, plan])
        #expect(library.resolveLink(NoteLink(name: "Plan"), in: reader) == .resolved(plan.id))
    }

    @Test func linksToOneNameBoundToDifferentNotesEachOpenTheirOwn() async throws {
        // [[Plan]] was bound to A; A was renamed and B took the title; [[Plan|new]] was then bound to B beside it.
        let a = item(ItemID("a"), "Plan v2"), b = item(ItemID("b"), "Plan")
        let source = item(reader, "Reader", links: [
            bound("Plan", .resolved(a.id)), bound("Plan|new", .resolved(b.id)), bound("Plan#Soil", .resolved(a.id)),
            bound("Plan#Soil|soil", .resolved(b.id))])
        let (library, _) = try await loaded([source, a, b])
        #expect(library.resolveLink(NoteLink(name: "Plan"), in: reader) == .resolved(a.id))
        #expect(library.resolveLink(NoteLink(name: "Plan", alias: "new"), in: reader) == .resolved(b.id))
        #expect(library.resolveLink(NoteLink(name: "Plan", heading: "Soil"), in: reader) == .resolved(a.id))
        #expect(library.resolveLink(NoteLink(name: "Plan", heading: "Soil", alias: "soil"), in: reader) == .resolved(b.id))
        // A spelling the copy has not bound is not borrowed from another.
        #expect(library.resolveLink(NoteLink(name: "Plan", alias: "other"), in: reader) == .pending)
    }

    @Test func whitespaceAndAnAliasThatRepeatsTheLinkDoNotMakeAnotherSpelling() async throws {
        let plan = item(ItemID("plan"), "Plan")
        let source = item(reader, "Reader", links: [bound("Plan | alias", .resolved(plan.id)), bound("Plan#Soil|Plan#Soil", .resolved(plan.id))])
        let (library, _) = try await loaded([source, plan])
        #expect(library.resolveLink(NoteLink(name: " Plan ", alias: "alias "), in: reader) == .resolved(plan.id))
        #expect(library.resolveLink(NoteLink(name: "Plan", heading: "Soil"), in: reader) == .resolved(plan.id))
    }

    @Test func anIdentityNamesThatNoteWhateverOtherNotesAreTitled() async throws {
        let target = ItemID(UUID().uuidString.lowercased())
        let decoy = ItemID(UUID().uuidString.lowercased())
        let (library, _) = try await loaded([
            item(reader, "Reader"), item(target, "Target"), item(decoy, target.rawValue)])
        #expect(library.resolveLink(NoteLink(name: target.rawValue), in: reader) == .resolved(target), "the copy answers an identity it holds without the server")
        #expect(library.resolveLink(NoteLink(name: decoy.rawValue, alias: "Decoy"), in: reader) == .resolved(decoy))
    }

    @Test func anIdentityTheLibraryDoesNotHoldIsPendingUntilTheServerAnswers() async throws {
        let (library, _) = try await loaded([item(reader, "Reader")])
        #expect(library.resolveLink(NoteLink(name: UUID().uuidString.lowercased()), in: reader) == .pending)
    }

    @Test func aRenamedNoteKeepsTheLinkTheCopyBoundToIt() async throws {
        let renamed = item(ItemID("renamed"), "Plan v2")
        let reused = item(ItemID("reused"), "Plan")
        let source = item(reader, "Reader", links: [bound("Plan", .resolved(renamed.id))])
        let (library, _) = try await loaded([source, renamed, reused])
        #expect(library.resolveLink(NoteLink(name: "Plan"), in: reader) == .resolved(renamed.id), "the copy keeps the note a spelling was bound to")
        #expect(library.resolveLink(NoteLink(name: "Plan"), in: renamed.id) == .pending, "from a note with no such link, nothing is bound yet")
    }

    @Test func whatTheCopyBoundALinkToIsWhatTheLinkNames() async throws {
        let plan = item(ItemID("plan"), "Plan")
        let source = item(reader, "Reader", links: [
            bound("Plan", .missing), bound("Twin", .ambiguous([])), bound("Banned", .refused("forbidden")), bound("Later", .pending)])
        let (library, _) = try await loaded([source, plan, item(ItemID("twin"), "Twin")])
        #expect(library.resolveLink(NoteLink(name: "Plan"), in: reader) == .missing)
        #expect(library.resolveLink(NoteLink(name: "Twin"), in: reader) == .ambiguous([]))
        #expect(library.resolveLink(NoteLink(name: "Banned"), in: reader) == .refused("forbidden"))
        #expect(library.resolveLink(NoteLink(name: "Later"), in: reader) == .pending)
    }

    @Test func aBoundNoteInTheBinIsMissingAndOneTheLibraryDoesNotHoldIsPending() async throws {
        let source = item(reader, "Reader", links: [bound("Bound", .resolved(ItemID("bound"))), bound("Elsewhere", .resolved(ItemID("elsewhere")))])
        let (library, _) = try await loaded([source, item(ItemID("bound"), "Bound", state: .trashed)])
        #expect(library.resolveLink(NoteLink(name: "Bound"), in: reader) == .missing, "bound to a note since deleted")
        #expect(library.resolveLink(NoteLink(name: "Elsewhere"), in: reader) == .pending)
    }

    @Test func aLinkFollowsTheCopyBindingItWhenTheNoteIsRead() async throws {
        let plan = item(ItemID("plan"), "Plan")
        let (library, source) = try await loaded([item(reader, "Reader"), plan])
        #expect(library.resolveLink(NoteLink(name: "Plan"), in: reader) == .pending)
        var read = try #require(library.item(reader))
        read.boundLinks = [bound("Plan", .resolved(plan.id))]
        read.version = ItemVersion(2)
        source.send(.upserted([read]))
        #expect(await eventually { library.resolveLink(NoteLink(name: "Plan"), in: reader) == .resolved(plan.id) })
    }
}

@Suite struct NoteLinkReadingTests {
    @Test func aLinkIsReadAsMarfaReadsTheTextBetweenItsBrackets() {
        #expect(NoteLink(reading: "Plan") == NoteLink(name: "Plan"))
        #expect(NoteLink(reading: " Plan ") == NoteLink(name: "Plan"))
        #expect(NoteLink(reading: "Plan|alias") == NoteLink(name: "Plan", alias: "alias"))
        #expect(NoteLink(reading: "Plan | alias") == NoteLink(name: "Plan", alias: "alias"))
        #expect(NoteLink(reading: "Plan#Soil") == NoteLink(name: "Plan", heading: "Soil"))
        #expect(NoteLink(reading: "Plan#Soil|soil") == NoteLink(name: "Plan", heading: "Soil", alias: "soil"))
        #expect(NoteLink(reading: "Plan|a#b") == NoteLink(name: "Plan", alias: "a#b"))
        #expect(NoteLink(reading: "Plan#Soil|Plan#Soil") == NoteLink(name: "Plan", heading: "Soil"), "an alias that repeats the link is none")
        #expect(NoteLink(reading: "Plan|").alias == nil)
        #expect(NoteLink(reading: "Plan#").heading == nil)
    }

    @Test func aLinkIsReadFromWhatThePagePosts() {
        #expect(NoteLink(page: ["target": "Plan"]) == NoteLink(name: "Plan"))
        #expect(NoteLink(page: ["target": "Plan", "heading": "Soil", "alias": "soil"]) == NoteLink(name: "Plan", heading: "Soil", alias: "soil"))
        #expect(NoteLink(page: ["heading": "Soil"]) == nil)
        #expect(MarfaMapping.inside(brackets: "[[Plan|a]]") == "Plan|a")
    }
}
