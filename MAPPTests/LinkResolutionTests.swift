import Foundation
import Testing
@testable import MAPP

/// What a `[[link]]` written in one note names, as a Marfa library reads it from its copy.
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
        source.send(.loaded(SourceSnapshot(items: items, catalogue: F.catalogue)))
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

    @Test func spacesInsideTheBracketsMakeAnotherSpellingMarfaBindsOnItsOwn() async throws {
        let a = item(ItemID("a"), "Plan"), b = item(ItemID("b"), "Plan two")
        let source = item(reader, "Reader", links: [bound("Plan | alias", .resolved(a.id)), bound("Plan|alias", .resolved(b.id))])
        let (library, _) = try await loaded([source, a, b])
        // InkKit hands the page the parts as written, spaces included.
        #expect(library.resolveLink(NoteLink(name: "Plan ", alias: " alias"), in: reader) == .resolved(a.id))
        #expect(library.resolveLink(NoteLink(name: "Plan", alias: "alias"), in: reader) == .resolved(b.id))
        // Spaces around the whole text are trimmed, as Marfa trims it.
        #expect(library.resolveLink(NoteLink(name: " Plan", alias: "alias "), in: reader) == .resolved(b.id))
    }

    @Test func anAliasThatRepeatsTheLinkIsTheLinkItself() async throws {
        let plan = item(ItemID("plan"), "Plan")
        let source = item(reader, "Reader", links: [bound("Plan#Soil|Plan#Soil", .resolved(plan.id))])
        let (library, _) = try await loaded([source, plan])
        #expect(library.resolveLink(NoteLink(name: "Plan", heading: "Soil"), in: reader) == .resolved(plan.id))
    }

    @Test func aLinkWithEscapedCharactersIsMatchedToWhatMarfaBoundItTo() async throws {
        let a = item(ItemID("a"), "A"), b = item(ItemID("b"), "B")
        // Marfa keeps the backslashes in the text it reports; InkKit hands the page the characters they stand for.
        let source = item(reader, "Reader", links: [
            bound("Plan|a\\#b", .resolved(a.id)), bound("Plan#A\\#B", .resolved(b.id)), bound("Plan#Soil|a\\|b", .missing)])
        let (library, _) = try await loaded([source, a, b])
        #expect(library.resolveLink(NoteLink(name: "Plan", alias: "a#b"), in: reader) == .resolved(a.id))
        #expect(library.resolveLink(NoteLink(name: "Plan", heading: "A#B"), in: reader) == .resolved(b.id))
        #expect(library.resolveLink(NoteLink(name: "Plan", heading: "Soil", alias: "a|b"), in: reader) == .missing)
        #expect(library.resolveLink(NoteLink(name: "Plan", alias: "a\\#b"), in: reader) == .pending, "the backslash is not part of the alias")
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
        #expect(NoteLink(reading: "Plan | alias") == NoteLink(name: "Plan ", alias: " alias"), "the spaces between the brackets stay")
        #expect(NoteLink(reading: "Plan | alias") != NoteLink(reading: "Plan|alias"))
        #expect(NoteLink(reading: "Plan | alias").lookupName == "Plan")
        #expect(NoteLink(reading: "Plan#Soil") == NoteLink(name: "Plan", heading: "Soil"))
        #expect(NoteLink(reading: "Plan#Soil|soil") == NoteLink(name: "Plan", heading: "Soil", alias: "soil"))
        #expect(NoteLink(reading: "Plan|a#b") == NoteLink(name: "Plan", alias: "a#b"))
        #expect(NoteLink(reading: "Plan#Soil|Plan#Soil") == NoteLink(name: "Plan", heading: "Soil"), "an alias that repeats the link is none")
        #expect(NoteLink(reading: "Plan|a\\#b") == NoteLink(name: "Plan", alias: "a#b"), "escapes are taken out")
        #expect(NoteLink(reading: "Plan#A\\#B") == NoteLink(name: "Plan", heading: "A#B"))
        #expect(NoteLink(reading: "Plan#Soil|a\\|b|c") == NoteLink(name: "Plan", heading: "Soil", alias: "a|b|c"))
        #expect(NoteLink(reading: "Plan|a\\x\\") == NoteLink(name: "Plan", alias: "a\\x\\"), "a backslash that escapes nothing stays")
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
