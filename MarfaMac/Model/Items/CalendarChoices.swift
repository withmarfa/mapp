import Foundation
import Marfa

/// What a view's calendar chooses: the date field it places items by, and whether its week shows Saturday and Sunday.
/// Unset members follow the defaults: each type's own date, and both days shown. Kept as a view's other Mac settings are
/// (`ViewMacSettings.calendar`, `PlaceDefault.calendar`).
nonisolated struct CalendarChoices: Codable, Hashable, Sendable {
    /// The key of the date field every item is placed by. Nil places each item by its own type's date.
    var date: String?
    var weekends: Bool?

    var showsWeekends: Bool { weekends ?? true }

    /// What the calendar places the items by.
    enum Placing: Equatable, Sendable {
        case eachType
        case field(String)
        /// The place has no date field to place by, so every item is left out.
        case nothing
    }

    /// The placing for the date fields the place's items can have. A field that is no longer one of them, because the
    /// place's types changed, gives way to the first date field without the stored choice being touched, so it takes
    /// effect again where its type returns.
    func placing(among fields: [ItemTypeInfo.Field]) -> Placing {
        guard let date else { return .eachType }
        if fields.contains(where: { $0.key == date }) { return .field(date) }
        return fields.first.map { .field($0.key) } ?? .nothing
    }
}
