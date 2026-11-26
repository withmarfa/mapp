import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// Where the page shows an item's properties, chosen for each type and kept in the defaults.
struct PagePlacementsTests {
    private static let ticket = TypeID("aic.ticket")
    private static let comment = TypeID("aic.comment")
    private static let person = TypeID("core.entity.person")

    private static func field(_ name: String, _ owner: String) -> TypeField {
        TypeField(name: name, type: "string", declaredBy: owner)
    }

    private static let catalogue = Catalogue(itemTypes: [
        MarfaMapping.itemType(ItemType(
            id: "aic.ticket", label: "Ticket", fields: [field("title", "aic.ticket"), field("github_id", "aic.ticket"), field("repo", "aic.ticket")],
            titleField: "title")),
        MarfaMapping.itemType(ItemType(
            id: "aic.comment", label: "Comment", fields: [field("title", "aic.comment"), field("github_id", "aic.comment")],
            titleField: "title", linkField: "github_id")),
        MarfaMapping.itemType(ItemType(id: "core.entity.person", label: "Person", fields: [], icon: "lucide:user")),
        MarfaMapping.itemType(ItemType(id: "aic.folder", label: "Folder", fields: [], roles: [MarfaMapping.containerRole])),
        MarfaMapping.itemType(ItemType(
            id: "aic.task", label: "Task",
            fields: [
                field("title", "aic.task"),
                TypeField(
                    name: "state", type: "status", declaredBy: "aic.task",
                    definition: ["status_values": [["value": "open", "group": "not_started"], ["value": "shut", "group": "completed"]]]),
            ],
            titleField: "title")),
        MarfaMapping.itemType(ItemType(id: "aic.subtask", label: "Subtask", parent: "aic.task", fields: [])),
    ])
    private static let task = TypeID("aic.task")
    private static let subtask = TypeID("aic.subtask")

    // MARK: Choices

    @Test func aChoiceOverridesTheDefaultEitherWay() {
        var placements = PagePlacements()
        placements.setShows(.whenSet, row: "github_id", of: Self.comment)
        placements.setShows(.hidden, row: "repo", of: Self.ticket)
        placements.setLinkedFrom(.page, of: Self.ticket, in: Self.catalogue)
        placements.setLinkedFrom(.inspector, of: Self.person, in: Self.catalogue)
        #expect(placements.placement(of: Self.comment, in: Self.catalogue).showsOnPage("github_id"))
        let ticket = placements.placement(of: Self.ticket, in: Self.catalogue)
        #expect(!ticket.showsOnPage("repo"))
        #expect(ticket.linkedFromPlace == .page)
        #expect(placements.placement(of: Self.person, in: Self.catalogue).linkedFromPlace == .inspector)
    }

    @Test func aLinkedFromPlaceEqualToTheTypesDefaultIsNotKept() {
        var placements = PagePlacements()
        placements.setLinkedFrom(.page, of: Self.ticket, in: Self.catalogue)
        #expect(placements.hasChoice(for: Self.ticket))
        // Back to the default, by either path, leaves no choice behind.
        placements.setLinkedFrom(.inspector, of: Self.ticket, in: Self.catalogue)
        #expect(!placements.hasChoice(for: Self.ticket))
        placements.set(true, row: PagePlacement.linkedFrom, of: Self.person, in: Self.catalogue)
        #expect(!placements.hasChoice(for: Self.person))
        placements.set(false, row: PagePlacement.linkedFrom, of: Self.person, in: Self.catalogue)
        #expect(placements.hasChoice(for: Self.person))
        placements.set(true, row: PagePlacement.linkedFrom, of: Self.person, in: Self.catalogue)
        #expect(!placements.hasChoice(for: Self.person))
        #expect(placements.rawValue == "{}")
    }

    @Test func aChoiceForOneTypeLeavesEveryOtherTypeAlone() {
        var placements = PagePlacements()
        placements.setShows(.hidden, row: "repo", of: Self.ticket)
        placements.setLinkedFrom(.page, of: Self.ticket, in: Self.catalogue)
        let comment = placements.placement(of: Self.comment, in: Self.catalogue)
        #expect(comment.showsOnPage("repo"))
        #expect(comment.linkedFromPlace == .inspector)
        #expect(!placements.hasChoice(for: Self.comment))
        #expect(placements.hasChoice(for: Self.ticket))
    }

    @Test func resettingATypeGivesItsDefaultsBack() {
        var placements = PagePlacements()
        placements.setShows(.hidden, row: "repo", of: Self.ticket)
        placements.setShows(.hidden, row: "repo", of: Self.comment)
        placements.reset(Self.ticket)
        #expect(placements.placement(of: Self.ticket, in: Self.catalogue).showsOnPage("repo"))
        #expect(!placements.placement(of: Self.comment, in: Self.catalogue).showsOnPage("repo"))
        #expect(!placements.hasChoice(for: Self.ticket))
    }

    // MARK: Stored value

    @Test func theChoiceRoundTripsThroughItsStoredText() {
        var placements = PagePlacements()
        placements.setShows(.hidden, row: "repo", of: Self.ticket)
        placements.setShows(.whenSet, row: "github_id", of: Self.comment)
        placements.setLinkedFrom(.page, of: Self.comment, in: Self.catalogue)
        #expect(PagePlacements(rawValue: placements.rawValue) == placements)
        #expect(PagePlacements().rawValue == "{}")
    }

    @Test func textThatIsNotAChoiceIsNotOne() {
        #expect(PagePlacements(rawValue: "not json") == nil)
        #expect(PagePlacements(rawValue: "[]") == nil)
    }

    /// A type's choice this version cannot read stays in the stored text beside the readable ones, and a reset of that
    /// type removes it.
    @Test func oneTypesChoiceThisVersionCannotReadStaysBesideTheRest() throws {
        let stored = #"{"aic.comment":{"linkedFrom":"somewhere"},"aic.ticket":{"rows":{"repo":false}}}"#
        var placements = try #require(PagePlacements(rawValue: stored))
        #expect(placements.placement(of: Self.ticket, in: Self.catalogue).showsOnPage("repo") == false)
        placements.setShows(.always, row: "repo", of: Self.ticket)
        #expect(placements.rawValue.contains(#""aic.comment":{"linkedFrom":"somewhere"}"#))
        placements.reset(Self.comment)
        #expect(!placements.rawValue.contains("aic.comment"))
    }

    @Test func aMemberThisVersionDoesNotReadSurvivesARewrite() throws {
        let stored = #"{"aic.ticket":{"linkedFrom":"inspector","rows":{"repo":false},"sidebar":["details","tags"]}}"#
        var placements = try #require(PagePlacements(rawValue: stored))
        placements.setShows(.always, row: "repo", of: Self.ticket)
        placements.setShows(.hidden, row: "github_id", of: Self.comment)
        #expect(
            placements.rawValue
                == #"{"aic.comment":{"rows":{"github_id":false},"shows":{"github_id":"hidden"}},"aic.ticket":{"linkedFrom":"inspector","rows":{"repo":true},"shows":{"repo":"always"},"sidebar":["details","tags"]}}"#)
    }

    @Test func theDefaultsHoldTheChoicesUnderOneKey() throws {
        let defaults = ThrowawayDefaults.make("MarfaMac.PagePlacementsTests")
        #expect(PagePlacements.stored(in: defaults) == PagePlacements())
        PagePlacements.update(in: defaults) { $0.setShows(.hidden, row: "repo", of: Self.ticket) }
        #expect(PagePlacements.stored(in: defaults).placement(of: Self.ticket, in: Self.catalogue).showsOnPage("repo") == false)
        PagePlacements.update(in: defaults) { $0.reset(Self.ticket) }
        #expect(PagePlacements.stored(in: defaults) == PagePlacements())
    }

    // MARK: Pins

    @Test func aSubtypeDoesNotFollowItsParentsPins() {
        var placements = PagePlacements()
        placements.setPins(["#source"], of: Self.task)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["#source"])
        #expect(placements.pins(of: Self.subtask, in: Self.catalogue) == ["child-of"])
    }

    @Test func aDefaultPinThatASavedChoiceTurnedOffStaysOff() {
        var placements = PagePlacements()
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["state", "child-of"], "the status and the parent")
        placements.setShows(.hidden, row: "state", of: Self.task)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["child-of"])
        // Showing it again gives the default pin back.
        placements.setShows(.whenSet, row: "state", of: Self.task)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["state", "child-of"])
    }

    @Test func aChosenListTakesThePlaceOfTheDefaultPins() {
        var placements = PagePlacements()
        placements.setPins(["#updated", "repo"], of: Self.ticket)
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#updated", "repo"])
        // A hidden row is the person's word about the property block; a pin they chose is theirs too.
        placements.setShows(.hidden, row: "repo", of: Self.ticket)
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#updated", "repo"])
    }

    @Test func aFifthPinIsRefusedAndTheListIsLeftAlone() {
        var placements = PagePlacements()
        placements.setPins(["#type", "#source", "#updated", "repo"], of: Self.ticket)
        var took = placements.pin("child-of", of: Self.ticket, in: Self.catalogue)
        #expect(!took)
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#type", "#source", "#updated", "repo"])
        // One already pinned stays pinned, where it is.
        took = placements.pin("#source", of: Self.ticket, in: Self.catalogue)
        #expect(took)
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#type", "#source", "#updated", "repo"])
        placements.unpin("#type", of: Self.ticket, in: Self.catalogue)
        took = placements.pin("child-of", of: Self.ticket, in: Self.catalogue)
        #expect(took)
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["#source", "#updated", "repo", "child-of"])
    }

    @Test func pinningStartsFromTheDefaultPinsAndMovingKeepsThemWithinTheList() {
        var placements = PagePlacements()
        let took = placements.pin("repo", of: Self.task, in: Self.catalogue)
        #expect(took)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["state", "child-of", "repo"])
        placements.movePin("repo", to: 0, of: Self.task, in: Self.catalogue)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["repo", "state", "child-of"])
        placements.movePin("repo", to: 99, of: Self.task, in: Self.catalogue)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["state", "child-of", "repo"])
        placements.movePin("gone", to: 0, of: Self.task, in: Self.catalogue)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["state", "child-of", "repo"])
    }

    @Test func fiveStoredPinsShowFourAndADuplicateCountsOnce() throws {
        let stored = try #require(PagePlacements(rawValue: ##"{"aic.ticket":{"rows":{},"pins":["#type","#type","repo","#source","#updated","child-of"]}}"##))
        #expect(stored.pins(of: Self.ticket, in: Self.catalogue) == ["#type", "repo", "#source", "#updated"])
        // The list in storage is not cut by reading it.
        #expect(stored.choices["aic.ticket"]?.pins?.count == 6)
    }

    @Test func aPinNamingAFieldTheTypeNoLongerHasStaysInStorage() throws {
        var placements = try #require(PagePlacements(rawValue: ##"{"aic.ticket":{"rows":{},"pins":["gone","#type"]}}"##))
        #expect(placements.pins(of: Self.ticket, in: Self.catalogue) == ["gone", "#type"])
        // Another change to the list does not drop it.
        placements.unpin("#type", of: Self.ticket, in: Self.catalogue)
        #expect(placements.choices["aic.ticket"]?.pins == ["gone"])
        #expect(PagePlacements(rawValue: placements.rawValue) == placements)
    }

    @Test func aChoiceSavedAsShownOrHiddenIsReadOnceAsThreeStatesWithNothingLost() throws {
        let old = #"{"aic.comment":{"rows":{"github_id":true}},"aic.ticket":{"linkedFrom":"page","pins":["repo"],"rowOrder":["repo"],"rows":{"repo":false}}}"#
        let placements = try #require(PagePlacements(rawValue: old))
        let ticket = try #require(placements.choices["aic.ticket"])
        #expect(ticket.shows == ["repo": .hidden])
        #expect(ticket.linkedFrom == .page)
        #expect(ticket.pins == ["repo"])
        #expect(ticket.rowOrder == ["repo"])
        #expect(placements.placement(of: Self.ticket, in: Self.catalogue).shows("repo") == .hidden)
        // A row shown that would be hidden by default, a connector's identifier, stays shown.
        #expect(placements.placement(of: Self.comment, in: Self.catalogue).shows("github_id") == .whenSet)
        #expect(placements.placement(of: Self.comment, in: Self.catalogue).shows("other_id") == .whenSet)
        // Written with `shows`, and `rows` beside it for an older copy, and read the same way again.
        let written = placements.rawValue
        #expect(written.contains(#""shows":{"repo":"hidden"}"#))
        #expect(written.contains(#""rows":{"repo":false}"#))
        #expect(PagePlacements(rawValue: written) == placements)
    }

    @Test func aChoiceWithOnlyShowsStillCarriesTheRowsAnOlderCopyRequires() throws {
        var placements = PagePlacements()
        placements.setShows(.always, row: "repo", of: Self.ticket)
        placements.setShows(.hidden, row: "state", of: Self.ticket)
        let written = placements.rawValue
        #expect(written.contains(#""rows":{"repo":true,"state":false}"#))
        // A choice with no placed row has one too, and a later `rows` that disagrees does not win over `shows`.
        placements.setPins([], of: Self.task)
        #expect(placements.rawValue.contains(#""aic.task":{"pins":[],"rows":{}}"#))
        let both = try #require(PagePlacements(rawValue: #"{"aic.ticket":{"rows":{"repo":false},"shows":{"repo":"always"}}}"#))
        #expect(both.choices["aic.ticket"]?.shows == ["repo": .always])
    }

    @Test func everyMemberAnotherCopyWroteSurvivesReadingAndWritingAgain() throws {
        let stored = #"{"aic.ticket":{"future":[1,{"a":null}],"labelOverrides":{"repo":"Repository"},"shows":{"repo":"always"},"sidebar":["history"]}}"#
        var placements = try #require(PagePlacements(rawValue: stored))
        placements.setPins(["repo"], of: Self.ticket)
        let again = try #require(PagePlacements(rawValue: placements.rawValue))
        let choice = try #require(again.choices["aic.ticket"])
        #expect(choice.others["labelOverrides"] == .object(["repo": .string("Repository")]))
        #expect(choice.others["future"] != nil)
        #expect(choice.others["sidebar"] == .array([.string("history")]))
        #expect(choice.pins == ["repo"])
        // A choice that holds only what this version does not name is not dropped as empty.
        let alone = try #require(PagePlacements(rawValue: #"{"aic.ticket":{"labelOverrides":{"repo":"Repository"}}}"#))
        #expect(alone.hasChoice(for: Self.ticket))
        #expect(alone.rawValue.contains("labelOverrides"))
    }

    @Test func aMoveKeepsTheSavedPlaceOfEveryRowThePageDoesNotList() {
        var placements = PagePlacements()
        // `pinned` and `absent` are saved rows this item does not list.
        placements.setRowOrder(["pinned", "a", "absent", "b", "c"], of: Self.ticket)
        // The page lists a, b, c; c moves above a.
        placements.moveRow("c", among: ["c", "a", "b"], of: Self.ticket)
        #expect(placements.choices["aic.ticket"]?.rowOrder == ["pinned", "c", "a", "absent", "b"])
        // a moves below b.
        placements.moveRow("a", among: ["c", "b", "a"], of: Self.ticket)
        #expect(placements.choices["aic.ticket"]?.rowOrder == ["pinned", "c", "absent", "b", "a"])
        // Move Down in the row's menu works the same way.
        placements.setRowOrder(["pinned", "a", "absent", "b"], of: Self.ticket)
        let moved = placements.move("a", by: 1, in: ["a", "b"], of: Self.ticket)
        #expect(moved)
        #expect(placements.choices["aic.ticket"]?.rowOrder == ["pinned", "absent", "b", "a"])
    }

    @Test func aMoveNamesTheRowsTheSavedOrderLacks() {
        var placements = PagePlacements()
        placements.moveRow("b", among: ["b", "a", "c"], of: Self.ticket)
        #expect(placements.choices["aic.ticket"]?.rowOrder == ["b", "a", "c"])
        placements.setRowOrder(["z"], of: Self.ticket)
        placements.moveRow("c", among: ["a", "c", "b"], of: Self.ticket)
        #expect(placements.choices["aic.ticket"]?.rowOrder == ["z", "a", "c", "b"])
    }

    @Test func aWordALaterVersionAddsIsSkippedAndTheRestIsKept() throws {
        let placements = try #require(PagePlacements(rawValue: #"{"aic.ticket":{"shows":{"repo":"always","state":"sometimes"}}}"#))
        #expect(placements.choices["aic.ticket"]?.shows == ["repo": .always])
    }

    @Test func aWordALaterVersionAddsSurvivesAnotherRowsChange() throws {
        var placements = try #require(PagePlacements(rawValue: #"{"aic.ticket":{"shows":{"repo":"always","state":"sometimes"}}}"#))
        placements.setPins(["repo"], of: Self.ticket)
        let text = placements.rawValue
        #expect(text.contains(#""state":"sometimes""#))
        #expect(text.contains(#""repo":"always""#))
        // A copy from before `shows` finds the row in `rows`.
        #expect(text.contains(#""rows":{"repo":true,"state":true}"#))
        // Only the row the person changes loses its kept word.
        placements.setShows(.hidden, row: "repo", of: Self.ticket)
        #expect(placements.rawValue.contains(#""state":"sometimes""#))
        placements.setShows(.always, row: "state", of: Self.ticket)
        #expect(!placements.rawValue.contains("sometimes"))
        #expect(placements.choices["aic.ticket"]?.shows == ["repo": .hidden, "state": .always])
    }

    @Test func aChoiceHoldingOnlyALaterWordIsNotDropped() throws {
        var placements = try #require(PagePlacements(rawValue: #"{"aic.ticket":{"shows":{"state":"sometimes"}}}"#))
        #expect(placements.hasChoice(for: Self.ticket))
        placements.setPins(["repo"], of: Self.ticket)
        placements.setPins([], of: Self.ticket)
        #expect(placements.rawValue.contains(#""state":"sometimes""#))
        #expect(PagePlacements(rawValue: placements.rawValue) == placements)
    }

    @Test func aDragKeepsTheOrderItNamesFoldedRowsIncluded() {
        var placements = PagePlacements()
        // `folded` is a row the page lists under Show More; c is dragged above a.
        placements.setRowOrder(["a", "folded", "b", "c"], of: Self.ticket)
        placements.setDraggedOrder(["c", "folded", "a", "b"], of: Self.ticket)
        #expect(placements.choices["aic.ticket"]?.rowOrder == ["c", "folded", "a", "b"])
    }

    @Test func aDragKeepsTheSavedPlaceOfRowsItDoesNotName() {
        var placements = PagePlacements()
        placements.setRowOrder(["pinned", "a", "absent", "folded", "b", "c"], of: Self.ticket)
        placements.setDraggedOrder(["c", "folded", "a", "b"], of: Self.ticket)
        #expect(placements.choices["aic.ticket"]?.rowOrder == ["pinned", "c", "folded", "a", "absent", "b"])
        // With nothing saved, the drag's order is the order.
        var fresh = PagePlacements()
        fresh.setDraggedOrder(["b", "a", "b"], of: Self.ticket)
        #expect(fresh.choices["aic.ticket"]?.rowOrder == ["b", "a"])
    }

    @Test func anOrderRoundTripsAndEachRowIsNamedOnce() throws {
        var ordered = PagePlacements()
        ordered.setRowOrder(["repo", "#tags", "repo"], of: Self.ticket)
        #expect(ordered.choices["aic.ticket"]?.rowOrder == ["repo", "#tags"], "each row once")
        #expect(PagePlacements(rawValue: ordered.rawValue) == ordered)
        ordered.setRowOrder(nil, of: Self.ticket)
        #expect(ordered == PagePlacements())
    }

    @Test func thePropertyBlockFollowsTheChosenOrderAndRowsNotNamedKeepTheirOrderAfterIt() {
        func row(_ id: String) -> PropertyRow { PropertyRow(id: id, label: id, value: .text(id)) }
        let candidates = ["a", "b", "c", "d"].map(row)
        var placements = PagePlacements()
        placements.setRowOrder(["c", "gone", "a"], of: Self.task)
        let placement = placements.placement(of: Self.task, in: Self.catalogue)
        #expect(placement.ordered(candidates, id: \.id).map(\.id) == ["c", "a", "b", "d"])
    }

    @Test func noPinsIsAChoiceThatSurvivesStorage() throws {
        var placements = PagePlacements()
        placements.setPins([], of: Self.task)
        #expect(placements.hasChoice(for: Self.task), "an empty list is not dropped as no choice")
        #expect(placements.pins(of: Self.task, in: Self.catalogue).isEmpty)
        let again = try #require(PagePlacements(rawValue: placements.rawValue))
        #expect(again == placements)
        #expect(again.choices["aic.task"]?.pins == [])
        #expect(again.pins(of: Self.task, in: Self.catalogue).isEmpty)
        #expect(PagePlacements(["aic.task": .init(pins: [])]).hasChoice(for: Self.task))
    }

    @Test func resettingATypeGivesItsDefaultPinsBackToo() {
        var placements = PagePlacements()
        placements.setPins(["#source"], of: Self.task)
        placements.setShows(.hidden, row: "repo", of: Self.ticket)
        placements.reset(Self.task)
        #expect(placements.pins(of: Self.task, in: Self.catalogue) == ["state", "child-of"])
        #expect(!placements.hasChoice(for: Self.task))
        #expect(placements.hasChoice(for: Self.ticket))
    }

    @Test func storedTextThatCannotBeReadIsSetAsideBeforeItIsWrittenOver() throws {
        let defaults = ThrowawayDefaults.make("PagePlacementsTests.setAside")
        let unreadable = #"{"aic.ticket":{"rows":{"repo":"not a flag"}}}"#
        defaults.set(unreadable, forKey: PagePlacements.key)

        PagePlacements.update(in: defaults) { $0.setShows(.hidden, row: "repo", of: Self.ticket) }
        PagePlacements.update(in: defaults) { $0.setShows(.whenSet, row: "repo", of: Self.ticket) }

        #expect(defaults.stringArray(forKey: PagePlacements.setAsideKey) == [unreadable])
        #expect(PagePlacements.stored(in: defaults).choices["aic.ticket"]?.shows == ["repo": .whenSet])
    }
}
