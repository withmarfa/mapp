import Foundation
import Marfa

extension ValueEditModel {
    var isDate: Bool {
        if case .date = kind { true } else { false }
    }

    var quickDates: [QuickDates.Entry] { QuickDates.entries(now: library.now(), calendar: request.calendar) }

    /// The quick dates above the calendar, then Not Set, which the panel draws below it.
    var quickRows: [ValueListRow] {
        quickDates.map {
            ValueListRow(
                id: "quick:" + $0.id, role: .option, title: $0.title,
                detail: QuickDates.detail(of: $0, now: library.now(), calendar: request.calendar, locale: .current, format: .stored()), mark: .symbol($0.symbol))
        } + [ValueListRow(id: ValueEditOptions.notSetID, role: .option, title: String(localized: "Not Set"), isCurrent: value == nil)]
    }

    var storedDate: ItemDate? { value?.string.flatMap { ItemDate.parse($0) } }

    /// A `datetime` field may hold a day or a moment; a `date` field never holds a time.
    var allowsTime: Bool {
        if case .date(let field) = kind, case .date(let includesTime) = field.kind { includesTime } else { false }
    }

    var hasTime: Bool { allowsTime && (storedDate?.hasTime ?? false) }

    /// The person chose a day from the quick dates, which keeps the time the value already has.
    func chooseDay(_ day: Date) {
        write(hasTime ? QuickDates.moment(on: day, keepingTimeOf: storedDate?.date, calendar: request.calendar) : day, withTime: hasTime)
    }

    /// The value's time as the person's locale writes it, or empty where the value holds none.
    var timeText: String {
        guard hasTime, let date = storedDate?.date else { return "" }
        return DateDisplay.timeOfDay(of: date, format: .stored(), calendar: request.calendar)
    }

    /// Writes what was typed in the time field: a time sets it on the day the value holds (today where it holds none),
    /// and nothing takes it away, leaving the day.
    /// Ending the panel, a time that can't be read is reported where the person will see it, since the panel's own
    /// notice goes with it.
    func commitTime(isEnding: Bool = false) {
        guard let draft = timeDraft else { return }
        timeDraft = nil
        guard allowsTime, isEditable else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            if hasTime, let date = storedDate?.date { write(date, withTime: false) }
            return
        }
        guard let time = TimeOfDay.parse(text) else {
            if isEnding {
                library.notices.tell(String(localized: "Time Not Saved"), String(localized: "“\(text)” isn’t a time, so the time wasn’t changed."))
            } else {
                notice = String(localized: "Enter a time such as 9:30.")
            }
            return
        }
        // Focus moving through the field leaves the time as it was, seconds included, and adds no undo step.
        if text == timeText { return }
        let day = storedDate?.date ?? library.now()
        write(request.calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day, withTime: true)
    }

    private func write(_ date: Date, withTime: Bool) {
        let text = withTime ? ItemDate.instant(date) : ItemDate.day(date, calendar: request.calendar)
        _ = commit(.string(text), failure: String(localized: "The date couldn’t be saved."))
    }

    func clearDate() {
        // A time typed and not yet written would otherwise set the date again as the panel closes.
        timeDraft = nil
        if commit(nil, failure: String(localized: "The date couldn’t be saved.")) { close() }
    }
}
