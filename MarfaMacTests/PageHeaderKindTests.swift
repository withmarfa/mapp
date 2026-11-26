import Foundation
import Marfa
import Testing
@testable import MarfaMac

struct PageHeaderKindTests {
    @Test func aTypeTakesTheKindOfTheNearestCoreTypeAboveIt() {
        let catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: TypeID("core.event"), label: "Event", fields: [], titleField: "title", bodyField: "body", parent: nil),
            ItemTypeInfo(id: TypeID("aic.meeting"), label: "Meeting", fields: [], titleField: "title", bodyField: "body", parent: TypeID("core.event")),
        ])
        #expect(PageHeaderKind.of(TypeID("aic.meeting"), in: catalogue) == .event)
        #expect(PageHeaderKind.of(TypeID("aic.other"), in: catalogue) == .general)
    }

    @Test func aTypeThatBuildsOnTheHighlightLeadsWithItsPassage() {
        let catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: TypeID("core.highlight"), label: "Highlight", fields: [], titleField: nil, bodyField: "text", parent: nil),
            ItemTypeInfo(id: TypeID("aic.quote"), label: "Quote", fields: [], titleField: nil, bodyField: "text", parent: TypeID("core.highlight")),
        ])
        #expect(PageHeaderKind.of(TypeID("aic.quote"), in: catalogue) == .highlight)
    }
}
