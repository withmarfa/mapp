import Foundation
import Observation
import Testing
@testable import MarfaMac

/// What a `marfa://` link does: it opens an item only in the Marfa it names and only one the copy holds, tells the
/// person why where it can't, waits only while the library opens, and never writes.
@Suite(.hangLimit)
struct ItemLinkRouteTests {
    nonisolated static let instance = "0195f3a2-7c4e-7b21-9a3d-5e6f7a8b9c0d"
    nonisolated static let other = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
    nonisolated static let item = ItemID("0195f3a2-8d11-7e42-8b5c-1a2b3c4d5e6f")

    private func link(_ instance: String = instance, _ item: ItemID = item) -> ItemAppLink {
        ItemAppLink(instanceID: instance, item: item)!
    }

    // MARK: The decision

    @Test func aHeldItemInTheConnectedMarfaOpens() {
        #expect(ItemLinkRoute.decide(link(), mode: .marfa, isLoaded: true, instanceID: Self.instance, holds: true) == .open(Self.item))
    }

    @Test func anotherMarfasLinkNeverOpens() {
        for holds in [true, false] {
            #expect(
                ItemLinkRoute.decide(link(Self.other), mode: .marfa, isLoaded: true, instanceID: Self.instance, holds: holds)
                    == .refuse(.otherMarfa))
        }
    }

    @Test func anItemTheCopyLacksIsNotFound() {
        #expect(ItemLinkRoute.decide(link(), mode: .marfa, isLoaded: true, instanceID: Self.instance, holds: false) == .refuse(.notFound))
    }

    @Test func aCopyThatDoesNotKnowItsMarfaOpensNothing() {
        #expect(ItemLinkRoute.decide(link(), mode: .marfa, isLoaded: true, instanceID: nil, holds: true) == .refuse(.notFound))
    }

    @Test func eachModeWithNoLibraryGivesItsAnswer() {
        func decide(_ mode: Libraries.Mode) -> ItemLinkRoute {
            ItemLinkRoute.decide(link(), mode: mode, isLoaded: false, instanceID: nil, holds: false)
        }
        #expect(decide(.unconfigured) == .refuse(.notConnected))
        #expect(decide(.failed) == .refuse(.unavailable))
        #expect(decide(.opening) == .wait)
        #expect(decide(.marfa) == .wait, "a library still loading is waited for")
    }

    @Test func onlyConnectingOffersSettingsAndEveryRefusalSaysSomething() {
        #expect(ItemLinkRefusal.notConnected.action == .openSettings(.connection))
        #expect(ItemLinkRefusal.unavailable.action == .openSettings(.connection))
        for refusal in ItemLinkRefusal.allCases {
            #expect(!refusal.message.isEmpty && !refusal.title.isEmpty)
            if refusal != .notConnected, refusal != .unavailable { #expect(refusal.action == nil) }
        }
    }

    // MARK: The opener

    /// What the windows show, which a test changes as the host would.
    @Observable @MainActor final class Standing {
        var mode: Libraries.Mode
        var library: FakeItemLibrary?

        init(_ mode: Libraries.Mode, _ library: FakeItemLibrary? = nil) {
            self.mode = mode
            self.library = library
        }

        var current: ItemLinkOpener.Standing { .init(mode: mode, library: mode == .marfa ? library : nil) }
    }

    @MainActor private func opener(
        _ standing: Standing, limit: Duration = .seconds(30), front: Browser? = nil
    ) -> (ItemLinkOpener, Notices) {
        let notices = Notices()
        let opener = ItemLinkOpener(notices: notices, limit: limit, front: { front }, activate: {}) { standing.current }
        return (opener, notices)
    }

    @MainActor private func library(holding state: ItemState = .active) -> FakeItemLibrary {
        let library = FakeItemLibrary()
        library.heldInstanceID = Self.instance
        _ = library.add("Kept", id: Self.item, state: state)
        return library
    }

    /// Everything a write to the fake leaves behind.
    @MainActor private func writes(_ library: FakeItemLibrary) -> [String] {
        [
            "\(library.items)", "\(library.bodies)", "\(library.created.count)", "\(library.bodyWrites.count)",
            "\(library.propertiesSet.count)", "\(library.typeChanges.count)", "\(library.restored.count)",
            "\(library.tagWrites.count)", "\(library.relationshipWrites.count)", "\(library.editedFields.count)",
            "\(library.chosenIcons.count)", "\(library.sourceChanges.count)", "\(library.addedFiles.count)",
            "\(library.attachedFiles.count)", "\(library.addedPlaces.count)", "\(library.downloadedAgain)",
            "\(library.itemsToPurge)", "\(library.views)",
        ]
    }

    private func url(_ text: String) -> URL { URL(string: text)! }

    @MainActor @Test func aMalformedLinkIsToldAndOpensNothing() async {
        let (opener, notices) = opener(Standing(.marfa, library()))
        opener.receive([url("marfa://\(Self.instance)/\(Self.item.rawValue)/")])
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.malformed.message])
        #expect(opener.request == nil)
    }

    @MainActor @Test func anAddressThatIsNotAMarfaLinkIsLeftAlone() async {
        let (opener, notices) = opener(Standing(.marfa, library()))
        opener.receive([url("com.withmarfa.marfa://callback?code=1"), url("https://example.com/\(Self.item.rawValue)")])
        #expect(notices.told == 0 && opener.request == nil)
    }

    @MainActor @Test func anotherMarfasLinkIsToldAndNoWindowIsAsked() async {
        let library = library()
        let (opener, notices) = opener(Standing(.marfa, library))
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link(Self.other).url])
        #expect(await eventually { notices.told == 1 })
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.otherMarfa.message])
        #expect(opener.request == nil && opened == 0)
    }

    @MainActor @Test func aHeldItemOpensInTheFrontWindowAndNothingIsWritten() async throws {
        let library = library()
        let browser = Browser()
        browser.adopt(library)
        let before = writes(library)
        let (opener, notices) = opener(Standing(.marfa, library), front: browser)
        let behind = Browser()
        opener.register(browser)
        opener.register(behind)
        var opened = 0
        opener.openMainWindow = { opened += 1 }

        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        #expect(opened == 0, "a window in front opens it, so no other is asked for")
        #expect(opener.take(for: behind, in: library) == nil, "another window leaves it")
        let item = try #require(opener.take(for: browser, in: library))
        #expect(item.id == Self.item && opener.request == nil)
        let defaults = UserDefaults(suiteName: "ItemLinkRouteTests.\(UUID().uuidString)")!
        browser.follow(link: item, in: library, order: ItemOrder(), defaults: defaults)
        #expect(browser.selection == [Self.item])
        #expect(notices.told == 0)
        #expect(writes(library) == before)
    }

    @MainActor @Test func withNoWindowOneIsOpenedAndTheFirstToShowTheLibraryTakesIt() async {
        let library = library()
        let (opener, _) = opener(Standing(.marfa, library))
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        #expect(opened == 1)
        #expect(opener.take(for: Browser(), in: FakeItemLibrary()) == nil, "a window on another library drops it")
        #expect(opener.request == nil)
    }

    @MainActor @Test func withNoWindowInFrontAnotherOpenOneTakesIt() async throws {
        let library = library()
        let (opener, _) = opener(Standing(.marfa, library))
        let browser = Browser()
        opener.register(browser)
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        #expect(opened == 0)
        #expect(try #require(opener.take(for: browser, in: library)).id == Self.item)
    }

    @MainActor @Test func anItemInRecentlyDeletedStillOpensAndNothingIsWritten() async throws {
        let library = library(holding: .trashed)
        let browser = Browser()
        browser.adopt(library)
        let before = writes(library)
        let (opener, _) = opener(Standing(.marfa, library), front: browser)
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        let item = try #require(opener.take(for: browser, in: library))
        #expect(item.state == .trashed)
        #expect(writes(library) == before)
    }

    @MainActor @Test func aMissingItemIsToldAsNotFound() async {
        let library = FakeItemLibrary()
        library.heldInstanceID = Self.instance
        let (opener, notices) = opener(Standing(.marfa, library))
        opener.receive([link().url])
        #expect(await eventually { notices.told == 1 })
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.notFound.message])
        #expect(opener.request == nil)
    }

    @MainActor @Test(arguments: [(Libraries.Mode.unconfigured, ItemLinkRefusal.notConnected), (.failed, .unavailable)])
    func noLibraryIsToldAndOnlyOffersSettings(_ mode: Libraries.Mode, _ refusal: ItemLinkRefusal) async {
        let (opener, notices) = opener(Standing(mode, library()))
        opener.receive([link().url])
        #expect(await eventually { notices.told == 1 })
        #expect(notices.waiting.map(\.message) == [refusal.message])
        #expect(notices.waiting.first?.action == .openSettings(.connection))
        #expect(opener.request == nil)
    }

    @MainActor @Test func aLinkWaitsForTheLibraryToOpen() async {
        let library = library()
        let standing = Standing(.opening, library)
        let (opener, notices) = opener(standing)
        opener.receive([link().url])
        // Gives the opener the chance to act on the link while the library opens, which it must not take.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(opener.request == nil && notices.told == 0)
        standing.mode = .marfa
        #expect(await eventually { opener.request != nil })
        #expect(opener.request?.item == Self.item && notices.told == 0)
    }

    @MainActor @Test func aNewerLinkReplacesAWaitingOne() async {
        let library = library()
        let newer = ItemID.mint()
        _ = library.add("Newer", id: newer)
        let standing = Standing(.opening, library)
        let (opener, notices) = opener(standing)
        opener.receive([link().url])
        opener.receive([link(Self.instance, newer).url])
        standing.mode = .marfa
        #expect(await eventually { opener.request != nil })
        #expect(opener.request?.item == newer && notices.told == 0)
    }

    @MainActor @Test func theLastOfSeveralLinksIsTheOneTaken() async {
        let library = library()
        let newer = ItemID.mint()
        _ = library.add("Newer", id: newer)
        let (opener, _) = opener(Standing(.marfa, library))
        opener.receive([link().url, link(Self.instance, newer).url])
        #expect(await eventually { opener.request != nil })
        #expect(opener.request?.item == newer)
    }

    @MainActor @Test func aLinkStopsWaitingAtItsLimit() async {
        let (opener, notices) = opener(Standing(.opening, library()), limit: .milliseconds(300))
        opener.receive([link().url])
        #expect(await eventually { notices.told == 1 })
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.stillOpening.message])
        #expect(opener.request == nil)
    }
}
