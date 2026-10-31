@testable import MAPP
import MarfaBrandIcons
import MarfaIcons
import Testing

@Suite(.hangLimit)
@MainActor struct TypeIconPickerTests {
    private let names = ["arrow-down", "arrow-up", "book", "book-open", "bookmark", "folder", "folder-open", "square-arrow-up"].map { "lucide:" + $0 }
    private func ids(_ names: [String]) -> [String] { names.map { "lucide:" + $0 } }

    @Test func emptySearchFindsEveryName() {
        #expect(IconNameSearch.matching("", in: names) == names)
        #expect(IconNameSearch.matching("  ", in: names) == names)
    }

    @Test func aWordFindsTheNamesThatContainIt() {
        #expect(IconNameSearch.matching("folder", in: names) == ids(["folder", "folder-open"]))
        #expect(IconNameSearch.matching("zzz", in: names).isEmpty)
    }

    @Test func caseSpacesAndHyphensDoNotMatter() {
        #expect(IconNameSearch.matching("Arrow Up", in: names) == ids(["arrow-up", "square-arrow-up"]))
        #expect(IconNameSearch.matching("arrow-up", in: names) == ids(["arrow-up", "square-arrow-up"]))
    }

    @Test func aNameThatStartsWithTheWordComesFirst() {
        #expect(IconNameSearch.matching("up", in: names) == ids(["arrow-up", "square-arrow-up"]))
        #expect(IconNameSearch.matching("book", in: names) == ids(["book", "book-open", "bookmark"]))
        #expect(IconNameSearch.matching("open", in: names) == ids(["book-open", "folder-open"]))
    }

    @Test func aNameThatStartsWithTheWordOutranksOneThatEndsWithIt() {
        let list = ids(["bookmark", "address-book", "book-open"])
        #expect(IconNameSearch.matching("book", in: list) == ids(["book-open", "bookmark", "address-book"]))
    }

    @Test func thePickerSavesTheFullIDOfABrandIcon() async {
        let library = FakeItemLibrary(items: [])
        let model = TypeIconPickerModel(type: TypeID("core.task"), library: library, ids: [.simpleIcons: ["simple-icons:github"]])
        model.set = .simpleIcons
        #expect(model.results == ["simple-icons:github"])
        #expect(await model.choose("simple-icons:github"))
        #expect(library.chosenIcons.map(\.icon) == ["simple-icons:github"])
        #expect(model.current == "simple-icons:github")
    }

    @Test func thePickerOpensOnTheSetOfTheTypesIcon() async {
        let library = FakeItemLibrary(items: [])
        #expect(TypeIconPickerModel(type: TypeID("core.task"), library: library).set == .lucide)
        _ = await library.setIcon("simple-icons:github", ofType: TypeID("core.task"))
        #expect(TypeIconPickerModel(type: TypeID("core.task"), library: library).set == .simpleIcons)
    }

    @Test func searchIgnoresTheSetPrefix() {
        let ids = ["lucide:book", "simple-icons:lucide", "lucide:lucide-thing"]
        #expect(IconNameSearch.matching("lucide", in: ids) == ["simple-icons:lucide", "lucide:lucide-thing"])
        #expect(IconNameSearch.matching("simple", in: ids).isEmpty, "the prefix is not part of the name")
    }

    @Test func theSetsComeFromTheSDKWithFullIDs() {
        #expect(IconSet.lucide.ids.contains("lucide:folder"))
        #expect(IconSet.lucide.ids.allSatisfy { $0.hasPrefix("lucide:") })
        #expect(IconSet.simpleIcons.ids.allSatisfy { $0.hasPrefix("simple-icons:") })
        #expect(IconSet(iconID: "folder") == nil, "a bare name belongs to no set")
        #expect(IconSet(iconID: "simple-icons:github") == .simpleIcons)
    }

    @Test func aBareNameDrawsTheFallbackAndABrandIDDraws() {
        MarfaBrandIcons.register()
        #expect(TypeIconArtwork(id: "folder") == .fallback)
        #expect(TypeIconArtwork(id: "lucide:folder") != .fallback)
        #expect(TypeIconArtwork(id: "simple-icons:github") == .brand("simple-icons:github"))
    }

    @Test func aNameReadsAsTitleCase() {
        #expect(IconNameSearch.title(of: "lucide:book-open") == "Book Open")
    }

    @Test func choosingAnIconShowsItAtOnce() async {
        let library = FakeItemLibrary(items: [])
        let model = TypeIconPickerModel(type: TypeID("core.task"), library: library, ids: [.lucide: ["lucide:bug", "lucide:zap"]])
        #expect(model.current == "lucide:list-checks")
        #expect(await model.choose("lucide:zap"))
        #expect(model.current == "lucide:zap")
        #expect(library.chosenIcons.map(\.icon) == ["lucide:zap"])
        #expect(model.failure == nil)
    }

    @Test func theGridAndCancelAreOffWhileAChoiceIsBeingWritten() async {
        let library = FakeItemLibrary(items: [])
        library.holdsIconAnswers = true
        let model = TypeIconPickerModel(type: TypeID("core.task"), library: library, ids: [.lucide: ["lucide:zap"]])
        #expect(model.canChoose && model.canCancel)
        let choice = Task { await model.choose("lucide:zap") }
        #expect(await eventually { model.isWorking })
        #expect(!model.canChoose, "a second choice cannot start")
        #expect(!model.canCancel, "the sheet stays open until the server answers")
        library.answerIcon()
        #expect(await choice.value)
        #expect(model.canChoose && model.canCancel)
    }

    @Test func theGridIsOffWithoutAServer() {
        let library = FakeItemLibrary(items: [])
        library.reachesServer = false
        let model = TypeIconPickerModel(type: TypeID("core.task"), library: library, ids: [.lucide: ["lucide:zap"]])
        #expect(!model.canChoose)
        #expect(model.canCancel)
    }

    @Test func aRefusalIsKeptForThePickerToShow() async {
        let library = FakeItemLibrary(items: [])
        library.iconFailure = .notPermitted
        let model = TypeIconPickerModel(type: TypeID("core.task"), library: library, ids: [.lucide: ["lucide:zap"]])
        #expect(await model.choose("lucide:zap") == false)
        #expect(model.failure == .notPermitted)
        #expect(model.current == "lucide:list-checks")
        #expect(TypeIconFailure.notPermitted.message.contains("can’t change the icon of a type"))
    }

    @Test func aSubtypeThatSetsNoIconTakesTheNewOne() {
        let parent = ItemTypeInfo(id: TypeID("a.parent"), label: "Parent", fields: [], titleField: nil, bodyField: nil, parent: nil, icon: "lucide:book")
        let child = ItemTypeInfo(id: TypeID("a.child"), label: "Child", fields: [], titleField: nil, bodyField: nil, parent: TypeID("a.parent"), icon: "lucide:book")
        let own = ItemTypeInfo(id: TypeID("a.own"), label: "Own", fields: [], titleField: nil, bodyField: nil, parent: TypeID("a.parent"), icon: "lucide:bug")
        let catalogue = Catalogue(itemTypes: [parent, child, own]).choosingIcon("lucide:zap", ofType: TypeID("a.parent"))
        #expect(catalogue.icon(for: TypeID("a.parent")) == "lucide:zap")
        #expect(catalogue.icon(for: TypeID("a.child")) == "lucide:zap")
        #expect(catalogue.icon(for: TypeID("a.own")) == "lucide:bug")
    }

    @Test func clearingAnIconWithNoAuthorsTakesTheParents() {
        let parent = ItemTypeInfo(id: TypeID("a.parent"), label: "Parent", fields: [], titleField: nil, bodyField: nil, parent: nil, icon: "lucide:book")
        let child = ItemTypeInfo(id: TypeID("a.child"), label: "Child", fields: [], titleField: nil, bodyField: nil, parent: TypeID("a.parent"), icon: "lucide:zap")
        let catalogue = Catalogue(itemTypes: [parent, child]).choosingIcon(nil, ofType: TypeID("a.child"))
        #expect(catalogue.icon(for: TypeID("a.child")) == "lucide:book")
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
        let (library, source) = try await open(.success("lucide:zap"))
        let task = TypeID("core.task")
        #expect(await library.setIcon("lucide:zap", ofType: task) == nil)
        #expect(library.catalogue.icon(for: task) == "lucide:zap")
        // The working copy has not heard of the change yet and still says the old icon.
        source.send(.catalogue(FakeItemLibrary.testCatalogue))
        #expect(await eventually { library.catalogue.icon(for: task) == "lucide:zap" })
    }

    @Test func theCopyCatchingUpEndsTheHold() async throws {
        let (library, source) = try await open(.success("lucide:zap"))
        let task = TypeID("core.task")
        _ = await library.setIcon("lucide:zap", ofType: task)
        var caughtUp = FakeItemLibrary.testCatalogue
        caughtUp.itemTypes[task]?.icon = "lucide:zap"
        source.send(.catalogue(caughtUp))
        var later = caughtUp
        later.itemTypes[task]?.icon = "lucide:bug"
        source.send(.catalogue(later))
        #expect(await eventually { library.catalogue.icon(for: task) == "lucide:bug" })
    }

    @Test func anotherAppsIconEndsTheHoldToo() async throws {
        let (library, source) = try await open(.success("lucide:zap"))
        let task = TypeID("core.task")
        _ = await library.setIcon("lucide:zap", ofType: task)
        // Another app then chose a different icon, which the copy reports without ever showing this one.
        var other = FakeItemLibrary.testCatalogue
        other.itemTypes[task]?.icon = "lucide:bug"
        source.send(.catalogue(other))
        #expect(await eventually { library.catalogue.icon(for: task) == "lucide:bug" })
    }

    @Test func aReadThatChangesAnotherTypeKeepsTheHold() async throws {
        let (library, source) = try await open(.success("lucide:zap"))
        let task = TypeID("core.task")
        _ = await library.setIcon("lucide:zap", ofType: task)
        var changed = FakeItemLibrary.testCatalogue
        let other = try #require(changed.itemTypes.keys.first { $0 != task })
        changed.itemTypes[other]?.icon = "lucide:bug"
        source.send(.catalogue(changed))
        #expect(await eventually { library.catalogue.icon(for: other) == "lucide:bug" })
        #expect(library.catalogue.icon(for: task) == "lucide:zap")
    }

    @Test func aRefusalChangesNothingAndSaysWhy() async throws {
        let (library, _) = try await open(.failure(.notPermitted))
        let task = TypeID("core.task")
        #expect(await library.setIcon("lucide:zap", ofType: task) == .notPermitted)
        #expect(library.catalogue.icon(for: task) == "lucide:list-checks")
    }

    @Test func aLibraryWithNoServerKeepsNoChoice() async {
        let library = MarfaLibrary(source: FakeItemSource(), notices: Notices())
        #expect(await library.setIcon("lucide:zap", ofType: TypeID("core.task")) == .unsupported)
        #expect(!library.reachesServer)
    }
}
