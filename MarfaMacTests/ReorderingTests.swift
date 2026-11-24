import Testing
@testable import MarfaMac

/// A row dropped on another in a panel's list takes its place, so it can be dragged either way and reach every place.
struct ReorderingTests {
    @Test func theAnchorIsTheRowItThenSitsBefore() {
        #expect(Reordering.anchor(dropping: "c", onto: "a", in: ["a", "b", "c"]) == "a", "dragged up, before the target")
        #expect(Reordering.anchor(dropping: "a", onto: "b", in: ["a", "b", "c"]) == "c", "dragged down, before the one after it")
        #expect(Reordering.anchor(dropping: "a", onto: "c", in: ["a", "b", "c"]) == nil, "or last")
    }
}
