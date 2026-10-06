import Foundation

/// The sections of the note list, as Notes groups them.
nonisolated enum NoteGroup: Hashable {
    case favorites
    case today
    case yesterday
    case previous7Days
    case previous30Days
    case month(year: Int, month: Int)
    case year(Int)

    func title(calendar: Calendar = .current) -> String {
        switch self {
        case .favorites: String(localized: "Favorites")
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .previous7Days: String(localized: "Previous 7 Days")
        case .previous30Days: String(localized: "Previous 30 Days")
        case .month(let year, let month):
            calendar.date(from: DateComponents(year: year, month: month))?
                .formatted(Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone).month(.wide)) ?? ""
        case .year(let year):
            calendar.date(from: DateComponents(year: year))?
                .formatted(Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone).year()) ?? ""
        }
    }

    static func group(for date: Date, now: Date, calendar: Calendar = .current) -> NoteGroup {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch daysAgo {
        case ...0: return .today
        case 1: return .yesterday
        case 2...7: return .previous7Days
        case 8...30: return .previous30Days
        default:
            let year = calendar.component(.year, from: date)
            guard year == calendar.component(.year, from: now) else { return .year(year) }
            return .month(year: year, month: calendar.component(.month, from: date))
        }
    }

    /// Sorts the items and splits them into sections. Favorites lead unless `favoritesFirst` is off, and date
    /// sections follow only when grouping by date and the list is sorted by a date.
    static func sections(
        of items: [Item],
        sort: NoteSort,
        favoritesFirst: Bool,
        groupsByDate: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> [NoteSection] {
        let items = sort.sorted(items)
        var sections: [NoteSection] = []
        var rest = items
        if favoritesFirst {
            let favorites = items.filter(\.isFavorite)
            if !favorites.isEmpty { sections.append(NoteSection(group: .favorites, items: favorites)) }
            rest = items.filter { !$0.isFavorite }
        }
        guard groupsByDate, sort != .title else {
            if !rest.isEmpty { sections.append(NoteSection(group: nil, items: rest)) }
            return sections
        }
        for item in rest {
            let group = group(for: sort.date(of: item), now: now, calendar: calendar)
            if sections.last?.group == group {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(NoteSection(group: group, items: [item]))
            }
        }
        return sections
    }
}

nonisolated struct NoteSection: Identifiable, Hashable {
    /// No group means the items are listed without a heading.
    var group: NoteGroup?
    var items: [Item]

    var id: NoteGroup? { group }
}
