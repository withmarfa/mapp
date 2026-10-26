import Testing
@testable import MAPP

struct ItemViewModeTests {
    private static let task = TypeID("example.task")
    private static let event = TypeID("example.event")
    private static let plain = TypeID("example.plain")
    private static let catalogue = Catalogue(itemTypes: [
        ItemTypeInfo(id: task, label: "Task", fields: [
            .init(key: "status", label: "Status", kind: .choice(["todo", "done"]), declaredBy: task),
        ], titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(id: event, label: "Event", fields: [
            .init(key: "starts_at", label: "Starts at", kind: .date(includesTime: true), declaredBy: event),
        ], titleField: "title", bodyField: "body", parent: nil),
        ItemTypeInfo(id: plain, label: "Plain", fields: [
            .init(key: "notes", label: "Notes", kind: .text, declaredBy: plain),
        ], titleField: "title", bodyField: "body", parent: nil),
    ])

    @Test func placesWithoutGroupingFieldsOfferNeitherBoardNorAgenda() {
        #expect(ItemViewMode.available(forTypes: [Self.plain], catalogue: Self.catalogue) == [.list, .gallery, .table])
        #expect(ItemViewMode.available(forTypes: [], catalogue: Self.catalogue) == [.list, .gallery, .table])
    }

    @Test func eachGroupingLayoutNeedsItsOwnKindOfField() {
        #expect(ItemViewMode.available(forTypes: [Self.task], catalogue: Self.catalogue) == [.list, .gallery, .table, .board])
        #expect(ItemViewMode.available(forTypes: [Self.event], catalogue: Self.catalogue) == [.list, .gallery, .table, .agenda])
    }

    @Test func mixedPlacesOfferEverythingAnyTypeCanShow() {
        #expect(ItemViewMode.available(forTypes: [Self.plain, Self.task, Self.event], catalogue: Self.catalogue) == ItemViewMode.allCases)
    }

    @Test func aWindowOnAnUnavailableLayoutReturnsToTheList() {
        let (library, _, _, _) = BrowserTests().makeFakeLibrary()
        let browser = Browser()
        browser.adopt(library)
        browser.viewMode = .board
        browser.fallBackToListIfUnavailable(in: library)
        #expect(browser.viewMode == .list)
        browser.viewMode = .table
        browser.fallBackToListIfUnavailable(in: library)
        #expect(browser.viewMode == .table)
    }

    @Test func openingAPlaceThatCannotShowTheLayoutFallsBackToTheList() {
        let (library, older, _, _) = BrowserTests().makeFakeLibrary()
        let home = FakeItemLibrary.collection("Home")
        library.items.append(home)
        let view = LibraryView(id: ItemID("v-reading"), title: "Reading")
        library.views = [view]
        library.viewMembers[view.id] = [older.id]
        let places: [SidebarItem] = [.collection(home.id), .view(view.id), .source("Web"), .itemType("core.note")]
        for place in places {
            let browser = Browser()
            browser.adopt(library)
            browser.viewMode = .board
            // The collections index has no layout of its own, so a trip through it must not lose the fallback.
            browser.show(.collections, in: library, order: NoteOrder())
            browser.show(place, in: library, order: NoteOrder())
            #expect(browser.viewMode == .list, "\(place)")
        }
    }
}
