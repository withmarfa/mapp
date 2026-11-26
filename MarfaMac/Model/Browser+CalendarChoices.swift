import Foundation

extension Browser {
    var calendarChoices: CalendarChoices {
        if let id = shown.savedView { return macSettings(for: id).calendar ?? CalendarChoices() }
        return placeCalendars[shown] ?? CalendarChoices()
    }

    /// Where the calendar stands its items, by the choice and the fields the place's types have.
    func calendarDating(in library: any ItemLibrary) -> CalendarChoices.Placing {
        calendarChoices.placing(among: timelineFieldChoices(in: library))
    }

    func changeCalendar(_ change: (inout CalendarChoices) -> Void) {
        if let id = shown.savedView {
            changeViewSettings(id) { $0.calendar = Self.changedCalendar($0.calendar, change) }
        } else {
            setPlaceCalendar(Self.changedCalendar(placeCalendars[shown], change), in: shown)
        }
    }

    private static func changedCalendar(_ stored: CalendarChoices?, _ change: (inout CalendarChoices) -> Void) -> CalendarChoices? {
        var choices = stored ?? CalendarChoices()
        change(&choices)
        return choices == CalendarChoices() ? nil : choices
    }

    private func setPlaceCalendar(_ stored: CalendarChoices?, in place: PlaceView) {
        let before = placeCalendars[place]
        guard before != stored else { return }
        placeCalendars[place] = stored
        updatePlaceDefault(place) { $0.calendar = stored }
        registerUndo(String(localized: "Change View")) { browser in
            guard browser.shown.isSame(place) else { return }
            browser.setPlaceCalendar(before, in: place)
        }
    }
}
