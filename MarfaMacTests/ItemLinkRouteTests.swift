import Foundation
import Observation
import Testing
@testable import MarfaMac

/// What a `marfa://` link does: it opens an item only in the Marfa it names and only one the copy holds and has not
/// deleted, in a main window that is open, tells the person why where it can't, waits only so long, and never writes.
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
        for state in [ItemState.active, .archived] {
            #expect(ItemLinkRoute.decide(link(), mode: .marfa, isLoaded: true, instanceID: Self.instance, held: state) == .open(Self.item))
        }
    }

    @Test func anotherMarfasLinkNeverOpens() {
        for held in [ItemState.active, .trashed, nil] {
            #expect(
                ItemLinkRoute.decide(link(Self.other), mode: .marfa, isLoaded: true, instanceID: Self.instance, held: held)
                    == .refuse(.otherMarfa))
        }
    }

    @Test func anItemTheCopyLacksIsNotFound() {
        #expect(ItemLinkRoute.decide(link(), mode: .marfa, isLoaded: true, instanceID: Self.instance, held: nil) == .refuse(.notFound))
    }

    @Test func anItemInRecentlyDeletedIsRefusedAndOnlyOffersRecentlyDeleted() {
        #expect(
            ItemLinkRoute.decide(link(), mode: .marfa, isLoaded: true, instanceID: Self.instance, held: .trashed)
                == .refuse(.inRecentlyDeleted))
        #expect(ItemLinkRefusal.inRecentlyDeleted.message == "This item is in Recently Deleted.")
        #expect(ItemLinkRefusal.inRecentlyDeleted.action == .openSettings(.recentlyDeleted))
    }

    @Test func aCopyThatDoesNotKnowItsMarfaSaysSoAndNotNotFound() {
        for held in [ItemState.active, nil] {
            #expect(
                ItemLinkRoute.decide(link(), mode: .marfa, isLoaded: true, instanceID: nil, held: held) == .refuse(.instanceUnknown))
        }
        #expect(ItemLinkRefusal.instanceUnknown.message != ItemLinkRefusal.notFound.message)
    }

    @Test func eachModeWithNoLibraryGivesItsAnswer() {
        func decide(_ mode: Libraries.Mode) -> ItemLinkRoute {
            ItemLinkRoute.decide(link(), mode: mode, isLoaded: false, instanceID: nil, held: nil)
        }
        #expect(decide(.unconfigured) == .refuse(.notConnected))
        #expect(decide(.failed) == .refuse(.unavailable))
        #expect(decide(.opening) == .wait)
        #expect(decide(.marfa) == .wait, "a library still loading is waited for")
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

    /// Records requests to bring the test window forward, and closes as a window does.
    @MainActor final class FakeWindow: ItemLinkWindow {
        var isOpen = true
        var whenClosed: (() -> Void)?
        private(set) var broughtForward = 0
        func bringForward() { broughtForward += 1 }

        func close() {
            isOpen = false
            whenClosed?()
        }
    }

    /// A main window as `MainView` is one: it tries to take the link each time the request changes.
    @MainActor final class FakeMainWindow {
        let browser = Browser()
        let window = FakeWindow()
        private(set) var opened: [ItemID] = []
        private let opener: ItemLinkOpener
        private let library: FakeItemLibrary

        init(_ opener: ItemLinkOpener, showing library: FakeItemLibrary) {
            self.opener = opener
            self.library = library
            opener.register(browser, window: window)
            watch()
        }

        private func watch() {
            withObservationTracking { _ = opener.request } onChange: {
                Task { @MainActor in
                    self.watch()
                    if let item = await self.opener.take(for: self.browser, in: self.library) { self.opened.append(item.id) }
                }
            }
        }
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

    /// Defaults of the test's own, holding Settings > General > Open Items.
    private func defaults(opening way: ItemOpening) -> UserDefaults {
        let suite = ThrowawayDefaults.make("ItemLinkRouteTests")
        suite.set(way.rawValue, forKey: ListKey.openItemsIn)
        return suite
    }

    @MainActor @Test func aMalformedLinkIsToldAndOpensNothing() async {
        let (opener, notices) = opener(Standing(.marfa, library()))
        opener.register(Browser(), window: FakeWindow())
        opener.receive([url("marfa://\(Self.instance)/\(Self.item.rawValue)/")])
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.malformed.message])
        #expect(opener.request == nil)
    }

    @MainActor @Test func anAddressThatIsNotAMarfaLinkIsLeftAlone() async {
        let (opener, notices) = opener(Standing(.marfa, library()))
        opener.receive([url("com.withmarfa.marfa://callback?code=1"), url("https://example.com/\(Self.item.rawValue)")])
        #expect(notices.told == 0 && opener.request == nil)
    }

    @MainActor @Test func anotherMarfasLinkIsToldInTheWindowInFront() async {
        let library = library()
        let browser = Browser()
        let (opener, notices) = opener(Standing(.marfa, library), front: browser)
        let window = FakeWindow()
        opener.register(browser, window: window)
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link(Self.other).url])
        #expect(await eventually { notices.told == 1 })
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.otherMarfa.message])
        #expect(opener.request == nil && opened == 0)
        #expect(window.broughtForward == 1, "a minimized window shows no notice, so it comes forward")
    }

    @MainActor @Test func aRefusalWithNoMainWindowOpensOneToBeSeen() async {
        let (opener, notices) = opener(Standing(.unconfigured))
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link().url])
        #expect(await eventually { notices.told == 1 })
        #expect(opened == 1)
        opener.receive([url("marfa://nothing")])
        #expect(notices.told == 2)
        #expect(opened == 1, "the window already asked for shows this one too")
    }

    @MainActor @Test func aHeldItemOpensInTheFrontWindowAndNothingIsWritten() async throws {
        let library = library()
        let browser = Browser()
        browser.adopt(library)
        let before = writes(library)
        let (opener, notices) = opener(Standing(.marfa, library), front: browser)
        let behind = Browser()
        let window = FakeWindow()
        opener.register(browser, window: window)
        opener.register(behind, window: FakeWindow())
        var opened = 0
        opener.openMainWindow = { opened += 1 }

        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        #expect(opened == 0, "a window in front opens it, so no other is asked for")
        #expect(await opener.take(for: behind, in: library) == nil, "another window leaves it")
        let item = try #require(await opener.take(for: browser, in: library))
        #expect(item.id == Self.item && opener.request == nil)
        #expect(window.broughtForward == 1)
        browser.open(itemLink: item, in: library, order: ItemOrder(), defaults: defaults(opening: .modal))
        #expect(browser.selection == [Self.item])
        #expect(notices.told == 0)
        #expect(writes(library) == before)
    }

    @MainActor @Test func withNoWindowOneIsOpenedAndTheFirstToShowTheCheckedLibraryTakesIt() async throws {
        let library = library()
        let standing = Standing(.marfa, library)
        let (opener, _) = opener(standing)
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        #expect(opened == 1)
        let browser = Browser()
        opener.register(browser, window: FakeWindow())
        #expect(await opener.take(for: browser, in: FakeItemLibrary()) == nil, "a window still on another library leaves it")
        #expect(opener.request != nil)
        #expect(try #require(await opener.take(for: browser, in: library)).id == Self.item)
    }

    @MainActor @Test func aRequestForALibraryTheWindowsHaveLeftIsDropped() async {
        let library = library()
        let standing = Standing(.marfa, library)
        let (opener, _) = opener(standing)
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        let other = self.library()
        standing.library = other
        #expect(await opener.take(for: Browser(), in: other) == nil, "the link was checked against the library before")
        #expect(opener.request == nil)
    }

    @MainActor @Test func severalLinksWithNoWindowOpenOnlyOne() async {
        let library = library()
        let newer = ItemID.mint()
        _ = library.add("Newer", id: newer)
        let (opener, _) = opener(Standing(.marfa, library))
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        opener.receive([link(Self.instance, newer).url])
        #expect(await eventually { opener.request?.item == newer })
        #expect(opened == 1)
    }

    @MainActor @Test func withNoWindowInFrontAnotherOpenOneTakesIt() async throws {
        let library = library()
        let (opener, _) = opener(Standing(.marfa, library))
        let browser = Browser()
        opener.register(browser, window: FakeWindow())
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        #expect(opened == 0)
        #expect(try #require(await opener.take(for: browser, in: library)).id == Self.item)
    }

    @MainActor @Test func aClosedWindowIsNeverChosen() async throws {
        let library = library()
        let closed = Browser()
        let (opener, _) = opener(Standing(.marfa, library), front: closed)
        let window = FakeWindow()
        window.isOpen = false
        opener.register(closed, window: window)
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        #expect(opener.request?.target == nil, "the window in front last has closed")
        #expect(opened == 1, "so a main window is opened for the link")
        let fresh = Browser()
        opener.register(fresh, window: FakeWindow())
        #expect(try #require(await opener.take(for: fresh, in: library)).id == Self.item)
    }

    @MainActor @Test func aWindowThatClosesBeforeTakingTheLinkLeavesItToAnother() async {
        let library = library()
        let target = Browser()
        let (opener, _) = opener(Standing(.marfa, library), front: target)
        let window = FakeWindow()
        opener.register(target, window: window)
        let other = FakeMainWindow(opener, showing: library)
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        // Lets the other window see the request, which is not its own.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(other.opened.isEmpty && opener.request != nil)
        window.close()
        #expect(await eventually { other.opened == [Self.item] })
        #expect(opened == 0)
    }

    @MainActor @Test func theLastWindowClosingBeforeTakingTheLinkAsksForAnother() async {
        let library = library()
        let target = Browser()
        let (opener, _) = opener(Standing(.marfa, library), front: target)
        let window = FakeWindow()
        opener.register(target, window: window)
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        window.close()
        #expect(await eventually { opened == 1 })
        let fresh = FakeMainWindow(opener, showing: library)
        // The fresh window takes the link as it does once restored.
        #expect(await opener.take(for: fresh.browser, in: library)?.id == Self.item)
    }

    // MARK: Delivery

    @MainActor @Test func aCopyThatNowHoldsAnotherMarfaOpensNothingAtDelivery() async {
        let library = library()
        let browser = Browser()
        let (opener, notices) = opener(Standing(.marfa, library), front: browser)
        opener.register(browser, window: FakeWindow())
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        // The copy filled from another Marfa at the same address, which holds an item with the same id.
        library.heldInstanceID = Self.other
        #expect(await opener.take(for: browser, in: library) == nil)
        #expect(opener.request == nil)
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.otherMarfa.message])
    }

    @MainActor @Test func deliveryWaitsOnlySoLongForTheCopy() async {
        let library = library()
        let browser = Browser()
        let (opener, notices) = opener(Standing(.marfa, library), limit: .milliseconds(300), front: browser)
        opener.register(browser, window: FakeWindow())
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        library.instanceIDDelay = .seconds(90)
        #expect(await opener.take(for: browser, in: library) == nil)
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.stillOpening.message])
    }

    @MainActor @Test func aNewerLinkDuringDeliveryStopsTheOlderOne() async {
        let library = library()
        let browser = Browser()
        let (opener, notices) = opener(Standing(.marfa, library), front: browser)
        opener.register(browser, window: FakeWindow())
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        library.instanceIDDelay = .seconds(90)
        let older = Task { await opener.take(for: browser, in: library) }
        // Lets the delivery start asking the copy which Marfa it is.
        try? await Task.sleep(for: .milliseconds(100))
        opener.receive([url("marfa://nothing")])
        #expect(await older.value == nil)
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.malformed.message])
    }

    // MARK: Asking for a main window

    @MainActor @Test func aMainWindowAskedForIsAskedForOnceUntilOneAppears() async {
        let library = library()
        let (opener, notices) = opener(Standing(.marfa, library))
        var opened = 0
        opener.openMainWindow = { opened += 1 }
        opener.receive([link().url])
        #expect(await eventually { opened == 1 })
        opener.receive([url("marfa://nothing")])
        opener.receive([link(Self.other).url])
        #expect(await eventually { notices.told == 2 })
        #expect(opened == 1, "the window asked for has yet to appear")
        let window = FakeMainWindow(opener, showing: library)
        window.window.close()
        opener.receive([url("marfa://nothing")])
        #expect(opened == 2, "the window that appeared has closed")
    }

    @MainActor @Test func aLinkBeforeAnySceneIsServedWhenTheFirstSceneAppears() async {
        let (opener, notices) = opener(Standing(.unconfigured))
        opener.receive([link().url])
        #expect(await eventually { notices.told == 1 })
        var opened = 0
        // Settings or an item's window appears, and no main window.
        opener.openMainWindow = { opened += 1 }
        #expect(await eventually { opened == 1 })
        opener.openMainWindow = { opened += 1 }
        // Gives a second scene's appearance the chance to ask again, which it must not.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(opened == 1)
    }

    @MainActor @Test func aMainWindowAppearingAtLaunchIsTheOnlyOneForALinkBeforeAnyScene() async {
        let (opener, notices) = opener(Standing(.unconfigured))
        opener.receive([url("marfa://nothing")])
        #expect(notices.told == 1)
        var opened = 0
        // The main window appears by itself: it gives the way to open windows and counts itself in the same update.
        opener.openMainWindow = { opened += 1 }
        opener.register(Browser(), window: FakeWindow())
        // Gives the waiting ask the chance to open a window, which it must not.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(opened == 0)
    }

    @MainActor @Test func anItemInRecentlyDeletedIsRefusedBeforeAnyWindowMoves() async {
        let library = library(holding: .trashed)
        let browser = Browser()
        browser.adopt(library)
        let before = writes(library)
        let (opener, notices) = opener(Standing(.marfa, library), front: browser)
        opener.register(browser, window: FakeWindow())
        opener.receive([link().url])
        #expect(await eventually { notices.told == 1 })
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.inRecentlyDeleted.message])
        #expect(notices.waiting.first?.action == .openSettings(.recentlyDeleted))
        #expect(opener.request == nil)
        #expect(browser.selection.isEmpty && !browser.isModalPresented)
        #expect(writes(library) == before)
    }

    @MainActor @Test func anItemMovedToRecentlyDeletedWhileWaitingIsRefusedAtDelivery() async throws {
        let library = library()
        let browser = Browser()
        let (opener, notices) = opener(Standing(.marfa, library), front: browser)
        opener.register(browser, window: FakeWindow())
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        let index = try #require(library.items.firstIndex { $0.id == Self.item })
        library.items[index].state = .trashed
        #expect(await opener.take(for: browser, in: library) == nil)
        #expect(opener.request == nil)
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.inRecentlyDeleted.message])
    }

    @MainActor @Test func aCopyWithNoInstanceIDSaysItCantCheckYet() async {
        let library = library()
        library.heldInstanceID = nil
        let (opener, notices) = opener(Standing(.marfa, library))
        opener.receive([link().url])
        #expect(await eventually { notices.told == 1 })
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.instanceUnknown.message])
        #expect(opener.request == nil)
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

    @MainActor @Test(arguments: ["refused", "malformed"])
    func aNewerLinkThatOpensNothingClearsARequestNotYetTaken(_ kind: String) async {
        let library = library()
        let browser = Browser()
        let (opener, notices) = opener(Standing(.marfa, library), front: browser)
        opener.register(browser, window: FakeWindow())
        opener.receive([link().url])
        #expect(await eventually { opener.request != nil })
        opener.receive([kind == "refused" ? link(Self.other).url : url("marfa://\(Self.instance)")])
        #expect(opener.request == nil, "the window must not open the older link after telling the newer one")
        #expect(await eventually { notices.told == 1 })
        #expect(await opener.take(for: browser, in: library) == nil)
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

    @MainActor @Test func theLimitCoversACopySlowToSayWhichMarfaItIs() async {
        let library = library()
        library.instanceIDDelay = .seconds(90)
        let (opener, notices) = opener(Standing(.marfa, library), limit: .milliseconds(300))
        opener.receive([link().url])
        #expect(await eventually(within: .seconds(10)) { notices.told == 1 })
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.stillOpening.message])
        #expect(opener.request == nil)
    }

    @MainActor @Test func aNewerLinkDoesNotWaitBehindACopySlowToAnswer() async {
        let library = library()
        library.instanceIDDelay = .seconds(90)
        let (opener, notices) = opener(Standing(.marfa, library))
        opener.receive([link().url])
        // Lets the opener start asking the copy which Marfa it is.
        try? await Task.sleep(for: .milliseconds(100))
        opener.receive([url("marfa://nothing")])
        #expect(notices.waiting.map(\.message) == [ItemLinkRefusal.malformed.message])
        library.instanceIDDelay = .zero
        opener.receive([link().url])
        #expect(await eventually(within: .seconds(10)) { opener.request != nil })
    }

    // MARK: The window

    @MainActor private func window(showing way: ItemOpening) -> (Browser, FakeItemLibrary, Item, UserDefaults) {
        let library = library()
        let browser = Browser()
        browser.adopt(library)
        return (browser, library, library.item(Self.item)!, defaults(opening: way))
    }

    @MainActor @Test func aLinkOpensOverTheListUnlessOpenItemsSaysFullPage() {
        for way in [ItemOpening.modal, .newWindow] {
            let (browser, library, item, defaults) = window(showing: way)
            var opened = 0
            browser.windowOpener = { _ in opened += 1 }
            browser.open(itemLink: item, in: library, order: ItemOrder(), defaults: defaults)
            #expect(browser.modalItem == Self.item && opened == 0, "a link never opens a window of its own")
        }
        let (browser, library, item, defaults) = window(showing: .fullPage)
        browser.open(itemLink: item, in: library, order: ItemOrder(), defaults: defaults)
        #expect(browser.isCollectionItemPresented && browser.modalItem == nil)
        #expect(browser.selection == [Self.item])
    }

    @MainActor @Test func aLinkReplacesWhatAnOpenModalShows() {
        let (browser, library, item, defaults) = window(showing: .fullPage)
        let shown = library.add("Shown")
        browser.open([shown.id], as: .modal, defaults: defaults)
        browser.open(itemLink: item, in: library, order: ItemOrder(), defaults: defaults)
        #expect(browser.modalItem == Self.item && !browser.isCollectionItemPresented)
    }
}
