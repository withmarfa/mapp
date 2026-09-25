import Foundation

/// The sections of the note list, as Notes groups them.
enum NoteGroup: Hashable {
    case pinned
    case today
    case yesterday
    case previous7Days
    case previous30Days
    case month(DateComponents)
    case year(Int)

    var title: String {
        switch self {
        case .pinned: String(localized: "Pinned")
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .previous7Days: String(localized: "Previous 7 Days")
        case .previous30Days: String(localized: "Previous 30 Days")
        case .month(let components):
            Calendar.current.date(from: components)?.formatted(.dateTime.month(.wide)) ?? ""
        case .year(let year): String(year)
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
            return .month(DateComponents(year: year, month: calendar.component(.month, from: date)))
        }
    }

    /// Splits notes already in display order into sections. Pinned notes lead unless `pinnedFirst` is off,
    /// and date sections follow only when the list is sorted by a date.
    static func sections(
        of notes: [Note],
        sort: NoteSort,
        pinnedFirst: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> [NoteSection] {
        var sections: [NoteSection] = []
        var rest = notes
        if pinnedFirst {
            let pinned = notes.filter(\.isPinned)
            if !pinned.isEmpty { sections.append(NoteSection(group: .pinned, notes: pinned)) }
            rest = notes.filter { !$0.isPinned }
        }
        guard sort != .title else {
            if !rest.isEmpty { sections.append(NoteSection(group: nil, notes: rest)) }
            return sections
        }
        for note in rest {
            let group = group(for: sort.date(of: note), now: now, calendar: calendar)
            if sections.last?.group == group {
                sections[sections.count - 1].notes.append(note)
            } else {
                sections.append(NoteSection(group: group, notes: [note]))
            }
        }
        return sections
    }
}

struct NoteSection: Identifiable, Hashable {
    /// No group means the notes are listed without a heading.
    var group: NoteGroup?
    var notes: [Note]

    var id: String { group.map { "\($0)" } ?? "all" }
}
