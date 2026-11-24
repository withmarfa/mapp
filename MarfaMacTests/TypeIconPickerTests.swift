@testable import MarfaMac
import Testing

@Suite(.hangLimit)
@MainActor struct TypeIconPickerTests {
    @Test func thePickerSavesTheFullIDOfABrandIcon() async {
        let library = FakeItemLibrary(items: [])
        let model = TypeIconPickerModel(type: TypeID("core.task"), library: library, ids: [.simpleIcons: ["simple-icons:github"]])
        model.set = .simpleIcons
        #expect(model.results == ["simple-icons:github"])
        #expect(await model.choose("simple-icons:github"))
        #expect(library.chosenIcons.map(\.icon) == ["simple-icons:github"])
        #expect(model.current == "simple-icons:github")
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
