import Foundation

/// The day a week starts on in every calendar and date panel MAPP draws, as Settings > General > Dates and Times says. A
/// setting kept as one value in the defaults (`key`), which syncs through the Marfa (`PreferencesMap`).
nonisolated enum WeekStart {
    static let key = "weekStart"

    /// Calendar weekdays, the first of which is Sunday, in the order the pop-up lists them.
    static let days = [1, 2, 3, 4, 5, 6, 7]

    /// The chosen weekday, or nil where the person leaves it to the system. A stored value that is not a weekday is
    /// the system's.
    static func stored(in defaults: UserDefaults = .standard) -> Int? {
        let day = defaults.integer(forKey: key)
        return days.contains(day) ? day : nil
    }

    /// `base` with the week starting where the person chose.
    static func calendar(_ base: Calendar, in defaults: UserDefaults = .standard) -> Calendar {
        guard let day = stored(in: defaults) else { return base }
        var calendar = base
        calendar.firstWeekday = day
        return calendar
    }
}

nonisolated extension Calendar {
    /// The current calendar with the week starting where Settings says. Every calendar MAPP draws uses it.
    static var mapp: Calendar { WeekStart.calendar(.current) }
}
