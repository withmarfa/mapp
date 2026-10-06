import Foundation
import Testing
@testable import MAPP

struct TypesBrowserTests {
    private let image = TypeSelection.item(TypeID("core.file.image"))
    private let pdf = TypeSelection.item(TypeID("core.file.pdf"))
    private let person = TypeSelection.item(TypeID("core.entity.person"))
    private let parentOf = TypeSelection.edge("parent-of")

    private func browser() -> TypesBrowser {
        TypesBrowser(catalogue: TypesFixtures.catalogue)
    }

    // MARK: Selection and history

    @Test func startsWithNothingChosenAndNowhereToGo() {
        let browser = browser()
        #expect(browser.selection == nil)
        #expect(!browser.canGoBack && !browser.canGoForward)
        #expect(browser.selectedItemType == nil && browser.selectedEdgeType == nil)
    }

    @Test func choosingATypeShowsItAndChoosingAnotherLetsBackReturn() {
        let browser = browser()
        browser.select(image)
        #expect(browser.selection == image)
        #expect(browser.selectedItemType?.type.label == "Image")
        #expect(!browser.canGoBack)
        browser.select(parentOf)
        #expect(browser.selectedEdgeType?.edge.id == "parent-of")
        #expect(browser.canGoBack && !browser.canGoForward)
        browser.goBack()
        #expect(browser.selection == image)
        #expect(!browser.canGoBack && browser.canGoForward)
        browser.goForward()
        #expect(browser.selection == parentOf)
    }

    @Test func choosingTheTypeAlreadyShownAddsNothingToTheHistory() {
        let browser = browser()
        browser.select(image)
        browser.select(image)
        browser.select(image)
        #expect(!browser.canGoBack)
        browser.select(pdf)
        browser.goBack()
        #expect(browser.selection == image)
        #expect(!browser.canGoBack)
    }

    @Test func aNewChoiceDropsWhatLayAhead() {
        let browser = browser()
        browser.select(image)
        browser.select(pdf)
        browser.select(person)
        browser.goBack()
        browser.goBack()
        #expect(browser.selection == image && browser.canGoForward)
        browser.select(parentOf)
        #expect(!browser.canGoForward)
        browser.goBack()
        #expect(browser.selection == image)
        #expect(!browser.canGoBack)
    }

    @Test func goingBackAndForwardWithNowhereToGoChangesNothing() {
        let browser = browser()
        browser.select(image)
        browser.goBack()
        browser.goForward()
        #expect(browser.selection == image)
    }

    @Test func aTypeTheCatalogueLacksCannotBeChosen() {
        let browser = browser()
        browser.select(image)
        browser.select(.item(TypeID("core.missing")))
        browser.select(.edge("missing"))
        #expect(browser.selection == image)
        #expect(!browser.canGoBack)
    }

    @Test func aTypeAndAnEdgeTypeOfTheSameIdAreTwoChoices() {
        let catalogue = Catalogue(
            itemTypes: [TypesFixtures.type("shared")], edgeTypes: [TypesFixtures.edge("shared")])
        let browser = TypesBrowser(catalogue: catalogue)
        browser.select(.item(TypeID("shared")))
        browser.select(.edge("shared"))
        #expect(browser.canGoBack)
        #expect(browser.selectedEdgeType != nil && browser.selectedItemType == nil)
    }

    @Test func clearingTheChoiceKeepsTheHistoryAndBackReturnsToIt() {
        let browser = browser()
        browser.select(image)
        browser.select(pdf)
        browser.select(nil)
        #expect(browser.selection == nil)
        #expect(browser.canGoBack)
        browser.goBack()
        #expect(browser.selection == pdf)
        browser.goBack()
        #expect(browser.selection == image)
    }

    @Test func choosingAgainAfterClearingIsTheSameStopNotANewOne() {
        let browser = browser()
        browser.select(image)
        browser.select(pdf)
        browser.select(nil)
        browser.select(pdf)
        browser.goBack()
        #expect(browser.selection == image)
        #expect(!browser.canGoBack)
    }

    @Test func aCatalogueThatLosesTheShownTypeClearsTheChoiceAndPrunesTheHistory() {
        let browser = browser()
        browser.select(image)
        browser.select(pdf)
        browser.select(person)
        var smaller = TypesFixtures.catalogue
        smaller.itemTypes[TypeID("core.entity.person")] = nil
        smaller.itemTypes[TypeID("core.file.pdf")] = nil
        browser.catalogue = smaller
        #expect(browser.selection == nil)
        #expect(browser.canGoBack)
        browser.goBack()
        #expect(browser.selection == image)
        #expect(!browser.canGoBack && !browser.canGoForward)
    }

    @Test func aCatalogueThatKeepsTheShownTypeKeepsTheHistory() {
        let browser = browser()
        browser.select(image)
        browser.select(pdf)
        var changed = TypesFixtures.catalogue
        changed.itemTypes[TypeID("core.entity")] = nil
        browser.catalogue = changed
        #expect(browser.selection == pdf)
        browser.goBack()
        #expect(browser.selection == image)
    }

    @Test func aCatalogueThatIsTransientlyEmptyKeepsTheChoiceAndTheHistory() {
        let browser = browser()
        browser.select(image)
        browser.select(pdf)
        browser.catalogue = Catalogue()
        #expect(browser.selection == pdf && browser.canGoBack)
        browser.catalogue = TypesFixtures.catalogue
        #expect(browser.selectedItemType?.type.label == "PDF")
        browser.goBack()
        #expect(browser.selection == image)
    }

    @Test func aReturningCatalogueThatLacksTheTypeThenClearsIt() {
        let browser = browser()
        browser.select(image)
        browser.catalogue = Catalogue()
        var smaller = TypesFixtures.catalogue
        smaller.itemTypes[TypeID("core.file.image")] = nil
        browser.catalogue = smaller
        #expect(browser.selection == nil)
    }

    // MARK: Revealing

    private let raw = TypeSelection.item(TypeID("core.file.image.raw"))

    @Test func choosingATypeOpensEveryTypeAboveIt() {
        let browser = browser()
        #expect(browser.expanded.isEmpty)
        browser.select(raw)
        #expect(browser.expanded == [TypeID("core.file"), TypeID("core.file.image")])
        #expect(!browser.isExpanded(TypeID("core.entity")))
    }

    @Test func choosingATypeUnderAMissingParentOpensWhatExists() {
        let browser = browser()
        browser.select(.item(TypeID("aic.ticket.bug")))
        #expect(browser.expanded.isEmpty)
    }

    @Test func backAndForwardOpenWhatTheyReturnTo() {
        let browser = browser()
        browser.select(raw)
        browser.select(person)
        browser.setExpanded(TypeID("core.file"), false)
        browser.setExpanded(TypeID("core.file.image"), false)
        browser.goBack()
        #expect(browser.selection == raw)
        #expect(browser.isExpanded(TypeID("core.file")) && browser.isExpanded(TypeID("core.file.image")))
    }

    @Test func aGroupOpensAndClosesAtTheListsRequestWithoutChangingTheChoice() {
        let browser = browser()
        browser.select(image)
        browser.setExpanded(TypeID("core.entity"), true)
        #expect(browser.isExpanded(TypeID("core.entity")))
        browser.setExpanded(TypeID("core.entity"), false)
        #expect(!browser.isExpanded(TypeID("core.entity")))
        #expect(browser.selection == image && !browser.canGoBack)
    }

    @Test func choosingAnEdgeTypeOpensNothing() {
        let browser = browser()
        browser.select(parentOf)
        #expect(browser.expanded.isEmpty)
    }

    @Test func aLoopOfParentsDoesNotHangTheReveal() {
        let catalogue = Catalogue(itemTypes: [
            TypesFixtures.type("a.one", parent: "a.two"), TypesFixtures.type("a.two", parent: "a.one")
        ])
        let browser = TypesBrowser(catalogue: catalogue)
        browser.select(.item(TypeID("a.one")))
        #expect(browser.expanded == [TypeID("a.two")])
    }

    // MARK: Search

    @Test func returnInTheSearchChoosesTheFirstMatchPassingOverTheTypesAboveIt() {
        let browser = browser()
        browser.searchText = "email"
        #expect(browser.itemRows.first?.type.label == "Entity")
        browser.selectFirstMatch()
        #expect(browser.selection == person)
    }

    @Test func returnInTheSearchChoosesAnEdgeTypeWhenNoItemTypeMatches() {
        let browser = browser()
        browser.searchText = "has-attachment"
        browser.selectFirstMatch()
        #expect(browser.selection == .edge("attached-to"))
    }

    @Test func returnInASearchWithNoMatchesKeepsTheChoice() {
        let browser = browser()
        browser.select(image)
        browser.searchText = "nothing like this"
        browser.selectFirstMatch()
        #expect(browser.selection == image)
        #expect(!browser.canGoBack)
    }

    private func labels(_ browser: TypesBrowser) -> [String] { browser.itemRows.map(\.type.label) }

    @Test func withoutASearchEveryTypeIsListed() {
        let browser = browser()
        #expect(!browser.isSearching)
        #expect(browser.itemRows.count == TypesFixtures.catalogue.itemTypes.count)
        #expect(browser.edgeTypes.count == 4)
        browser.searchText = "   "
        #expect(!browser.isSearching)
        #expect(browser.itemRows.count == TypesFixtures.catalogue.itemTypes.count)
    }

    @Test func searchMatchesIdLabelFieldNamesAndReverseNames() {
        let browser = browser()
        browser.searchText = "core.entity.pers"
        #expect(labels(browser).contains("Person"))
        browser.searchText = "Contact"
        #expect(labels(browser) == ["Contact"])
        browser.searchText = "email"
        #expect(labels(browser) == ["Entity", "Person"])
        browser.searchText = "has-attach"
        #expect(browser.edgeTypes.map(\.id) == ["attached-to"])
        #expect(browser.itemRows.isEmpty)
        browser.searchText = "child-of"
        #expect(browser.edgeTypes.map(\.id) == ["parent-of"])
    }

    @Test func searchIgnoresCaseAndDiacritics() {
        let catalogue = Catalogue(
            itemTypes: [TypesFixtures.type("aic.cafe", "Café"), TypesFixtures.type("aic.other", "Other")],
            edgeTypes: [TypesFixtures.edge("serves", "Sérvés")])
        let browser = TypesBrowser(catalogue: catalogue)
        browser.searchText = "cafe"
        #expect(labels(browser) == ["Café"])
        browser.searchText = "CAFÉ"
        #expect(labels(browser) == ["Café"])
        browser.searchText = "SERVES"
        #expect(browser.edgeTypes.map(\.id) == ["serves"])
    }

    @Test func searchMatchesAFieldsLabelAsWellAsItsKey() {
        let catalogue = Catalogue(itemTypes: [
            TypesFixtures.type("aic.task", "Task", fields: [TypesFixtures.field("due_at", .date, by: "aic.task")]),
            TypesFixtures.type("aic.note", "Note")
        ])
        let browser = TypesBrowser(catalogue: catalogue)
        browser.searchText = "due at"
        #expect(labels(browser) == ["Task"])
        browser.searchText = "due_at"
        #expect(labels(browser) == ["Task"])
    }

    @Test func aMatchingSubtypeStaysUnderItsParentsForContext() {
        let browser = browser()
        browser.searchText = "exposure"
        let tree = browser.itemTree
        #expect(tree.map(\.type.label) == ["File"])
        #expect(tree[0].matchesSearch == false)
        let image = tree[0].children?.first
        #expect(image?.type.label == "Image" && image?.matchesSearch == false)
        let raw = image?.children?.first
        #expect(raw?.type.label == "Raw Image" && raw?.matchesSearch == true)
        #expect(browser.itemRows.map(\.depth) == [0, 1, 2])
    }

    @Test func aSearchDoesNotShowSiblingsThatDoNotMatch() {
        let browser = browser()
        browser.searchText = "pdf"
        #expect(labels(browser) == ["File", "PDF"])
    }

    @Test func aSearchWithNoMatchHasNoResults() {
        let browser = browser()
        browser.searchText = "zzz"
        #expect(browser.itemRows.isEmpty && browser.edgeTypes.isEmpty)
        #expect(!browser.hasResults)
        #expect(browser.isSearching)
    }

    @Test func searchingDoesNotChangeTheChoice() {
        let browser = browser()
        browser.select(image)
        browser.searchText = "zzz"
        #expect(browser.selection == image)
        #expect(browser.selectedItemType != nil)
    }
}
