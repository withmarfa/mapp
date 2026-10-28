@testable import MAPP
import Testing

@Suite(.hangLimit)
@MainActor struct TypeIconPickerTests {
    private let names = ["arrow-down", "arrow-up", "book", "book-open", "bookmark", "folder", "folder-open", "square-arrow-up"]

    @Test func emptySearchFindsEveryName() {
        #expect(IconNameSearch.matching("", in: names) == names)
        #expect(IconNameSearch.matching("  ", in: names) == names)
    }

    @Test func aWordFindsTheNamesThatContainIt() {
        #expect(IconNameSearch.matching("folder", in: names) == ["folder", "folder-open"])
        #expect(IconNameSearch.matching("zzz", in: names).isEmpty)
    }

    @Test func caseSpacesAndHyphensDoNotMatter() {
        #expect(IconNameSearch.matching("Arrow Up", in: names) == ["arrow-up", "square-arrow-up"])
        #expect(IconNameSearch.matching("arrow-up", in: names) == ["arrow-up", "square-arrow-up"])
    }

    @Test func aNameThatStartsWithTheWordComesFirst() {
        #expect(IconNameSearch.matching("up", in: names) == ["arrow-up", "square-arrow-up"])
        #expect(IconNameSearch.matching("book", in: names) == ["book", "book-open", "bookmark"])
        #expect(IconNameSearch.matching("open", in: names) == ["book-open", "folder-open"])
    }

    @Test func aNameThatStartsWithTheWordOutranksOneThatEndsWithIt() {
        let list = ["bookmark", "address-book", "book-open"]
        #expect(IconNameSearch.matching("book", in: list) == ["book-open", "bookmark", "address-book"])
    }

    @Test func aNameReadsAsTitleCase() {
        #expect(IconNameSearch.title(of: "book-open") == "Book Open")
    }

    @Test func choosingAnIconShowsItAtOnce() async {
        let library = FakeItemLibrary(items: [])
        let model = TypeIconPickerModel(type: TypeID("core.task"), library: library, names: ["bug", "zap"])
        #expect(model.current == "list-checks")
        #expect(await model.choose("zap"))
        #expect(model.current == "zap")
        #expect(library.chosenIcons.map(\.icon) == ["zap"])
        #expect(model.failure == nil)
    }

    @Test func theGridAndCancelAreOffWhileAChoiceIsBeingWritten() async {
        let library = FakeItemLibrary(items: [])
        library.holdsIconAnswers = true
        let model = TypeIconPickerModel(type: TypeID("core.task"), library: library, names: ["zap"])
        #expect(model.canChoose && model.canCancel)
        let choice = Task { await model.choose("zap") }
        #expect(await eventually { model.isWorking })
        #expect(!model.canChoose, "a second choice cannot start")
        #expect(!model.canCancel, "the sheet stays open until the server answers")
        library.answerIcon()
        #expect(await choice.value)
        #expect(model.canChoose && model.canCancel)
    }

    @Test func theGridIsOffWithoutAServer() {
        let library = FakeItemLibrary(items: [])
        library.canChooseTypeIcons = false
        let model = TypeIconPickerModel(type: TypeID("core.task"), library: library, names: ["zap"])
        #expect(!model.canChoose)
        #expect(model.canCancel)
    }

    @Test func aRefusalIsKeptForThePickerToShow() async {
        let library = FakeItemLibrary(items: [])
        library.iconFailure = .notPermitted
        let model = TypeIconPickerModel(type: TypeID("core.task"), library: library, names: ["zap"])
        #expect(await model.choose("zap") == false)
        #expect(model.failure == .notPermitted)
        #expect(model.current == "list-checks")
        #expect(TypeIconFailure.notPermitted.message.contains("can’t change the icon of a type"))
    }

    @Test func aSubtypeThatSetsNoIconTakesTheNewOne() {
        let parent = ItemTypeInfo(id: TypeID("a.parent"), label: "Parent", fields: [], titleField: nil, bodyField: nil, parent: nil, icon: "book")
        let child = ItemTypeInfo(id: TypeID("a.child"), label: "Child", fields: [], titleField: nil, bodyField: nil, parent: TypeID("a.parent"), icon: "book")
        let own = ItemTypeInfo(id: TypeID("a.own"), label: "Own", fields: [], titleField: nil, bodyField: nil, parent: TypeID("a.parent"), icon: "bug")
        let catalogue = Catalogue(itemTypes: [parent, child, own]).choosingIcon("zap", ofType: TypeID("a.parent"))
        #expect(catalogue.icon(for: TypeID("a.parent")) == "zap")
        #expect(catalogue.icon(for: TypeID("a.child")) == "zap")
        #expect(catalogue.icon(for: TypeID("a.own")) == "bug")
    }

    @Test func clearingAnIconWithNoAuthorsTakesTheParents() {
        let parent = ItemTypeInfo(id: TypeID("a.parent"), label: "Parent", fields: [], titleField: nil, bodyField: nil, parent: nil, icon: "book")
        let child = ItemTypeInfo(id: TypeID("a.child"), label: "Child", fields: [], titleField: nil, bodyField: nil, parent: TypeID("a.parent"), icon: "zap")
        let catalogue = Catalogue(itemTypes: [parent, child]).choosingIcon(nil, ofType: TypeID("a.child"))
        #expect(catalogue.icon(for: TypeID("a.child")) == "book")
    }
}

private struct FakeTypeIcons: TypeIconSource {
    var answer: Result<String?, TypeIconFailure>
    func setIcon(_ icon: String?, ofType type: TypeID) async throws(TypeIconFailure) -> String? {
        try answer.get()
    }
}

@Suite(.hangLimit)
@MainActor struct MarfaLibraryTypeIconTests {
    private func open(_ answer: Result<String?, TypeIconFailure>) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices(), typeIcons: FakeTypeIcons(answer: answer))
        source.send(.loaded(SourceSnapshot(items: [], catalogue: FakeItemLibrary.testCatalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    @Test func theAnsweredIconIsDrawnAtOnceAndSurvivesAStaleRead() async throws {
        let (library, source) = try await open(.success("zap"))
        let task = TypeID("core.task")
        #expect(await library.setIcon("zap", ofType: task) == nil)
        #expect(library.catalogue.icon(for: task) == "zap")
        // The working copy has not heard of the change yet and still says the old icon.
        source.send(.catalogue(FakeItemLibrary.testCatalogue))
        #expect(await eventually { library.catalogue.icon(for: task) == "zap" })
    }

    @Test func theCopyCatchingUpEndsTheHold() async throws {
        let (library, source) = try await open(.success("zap"))
        let task = TypeID("core.task")
        _ = await library.setIcon("zap", ofType: task)
        var caughtUp = FakeItemLibrary.testCatalogue
        caughtUp.itemTypes[task]?.icon = "zap"
        source.send(.catalogue(caughtUp))
        var later = caughtUp
        later.itemTypes[task]?.icon = "bug"
        source.send(.catalogue(later))
        #expect(await eventually { library.catalogue.icon(for: task) == "bug" })
    }

    @Test func anotherAppsIconEndsTheHoldToo() async throws {
        let (library, source) = try await open(.success("zap"))
        let task = TypeID("core.task")
        _ = await library.setIcon("zap", ofType: task)
        // Another app then chose a different icon, which the copy reports without ever showing this one.
        var other = FakeItemLibrary.testCatalogue
        other.itemTypes[task]?.icon = "bug"
        source.send(.catalogue(other))
        #expect(await eventually { library.catalogue.icon(for: task) == "bug" })
    }

    @Test func aReadThatChangesAnotherTypeKeepsTheHold() async throws {
        let (library, source) = try await open(.success("zap"))
        let task = TypeID("core.task")
        _ = await library.setIcon("zap", ofType: task)
        var changed = FakeItemLibrary.testCatalogue
        let other = try #require(changed.itemTypes.keys.first { $0 != task })
        changed.itemTypes[other]?.icon = "bug"
        source.send(.catalogue(changed))
        #expect(await eventually { library.catalogue.icon(for: other) == "bug" })
        #expect(library.catalogue.icon(for: task) == "zap")
    }

    @Test func aRefusalChangesNothingAndSaysWhy() async throws {
        let (library, _) = try await open(.failure(.notPermitted))
        let task = TypeID("core.task")
        #expect(await library.setIcon("zap", ofType: task) == .notPermitted)
        #expect(library.catalogue.icon(for: task) == "list-checks")
    }

    @Test func aLibraryWithNoServerKeepsNoChoice() async {
        let library = MarfaLibrary(source: FakeItemSource(), notices: Notices())
        #expect(await library.setIcon("zap", ofType: TypeID("core.task")) == .unsupported)
        #expect(!library.canChooseTypeIcons)
    }
}
