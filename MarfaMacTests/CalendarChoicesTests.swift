import Foundation
import Testing
@testable import MarfaMac

struct CalendarChoicesTests {
    private let type = TypeID("test.event")

    private func field(_ key: String) -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(key: key, label: key, kind: .date(includesTime: false), declaredBy: type)
    }

    @Test func aChoiceThatIsNoLongerAFieldFallsBackWithoutBeingRewritten() {
        let choices = CalendarChoices(date: "due", weekends: nil)
        #expect(choices.placing(among: [field("start"), field("due")]) == .field("due"))
        #expect(choices.placing(among: [field("start"), field("end")]) == .field("start"), "the first field stands in")
        #expect(choices.placing(among: []) == .nothing, "no date field puts every item under No Date")
        #expect(choices.date == "due", "the stored choice is read, never rewritten")
        #expect(CalendarChoices().placing(among: []) == .eachType)
    }
}
