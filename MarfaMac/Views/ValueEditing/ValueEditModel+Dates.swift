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

    /// The time field took focus, showing the value's own time unless something typed is still in it.
    func beginTime() {
        if unsaved == nil { shownValue = value }
    }

    /// Whether the value already holds the time `text` asks for: none where it is empty.
    func holdsTime(_ text: String) -> Bool {
        guard !text.isEmpty else { return !hasTime }
        guard hasTime, let time = TimeOfDay.parse(text), let date = storedDate?.date else { return false }
        let held = request.calendar.dateComponents([.hour, .minute], from: date)
        return held.hour == time.hour && held.minute == time.minute
    }

    /// The value's time as the person's locale writes it, or empty where the value holds none.
    var timeText: String { timeText(of: value) }

    func timeText(of value: PropertyValue?) -> String {
        guard allowsTime, let date = value?.string.flatMap({ ItemDate.parse($0) }), date.hasTime else { return "" }
        return DateDisplay.timeOfDay(of: date.date, format: .stored(), calendar: request.calendar)
    }

    /// Writes the time typed (`unsaved`): a time sets it on the day the value holds (today where it holds none), and
    /// nothing takes it away, leaving the day. It is written only while the value holds what it was typed against;
    /// otherwise, where the item can't be edited, and, as the panel ends, where it can't be read or the library
    /// refuses it, it goes back to the person. While the panel is open, a refused or unreadable time stays in the field.
    func commitTime(isEnding: Bool = false) {
        guard allowsTime, let input = unsaved else { return }
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = TimeOfDay.parse(text)
        // The person changed nothing, or the value already holds their time (saved from another device, say): there
        // is nothing to write or to lose, and focus passing through the field adds no undo step.
        if text == timeText(of: input.base) || holdsTime(text) {
            unsaved = nil
            return
        }
        guard isEditable else { return handBackUnsaved() }
        guard value == input.base else {
            return handBackUnsaved(reason: String(localized: "This value changed while you were editing. Your edit hasn’t been saved."))
        }
        let written: Bool
        if text.isEmpty {
            guard let date = storedDate?.date else { return unsaved = nil }
            written = write(date, withTime: false)
        } else if let time {
            let day = storedDate?.date ?? library.now()
            written = write(request.calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day, withTime: true)
        } else if isEnding {
            return handBackUnsaved(reason: String(localized: "“\(text)” isn’t a time, so the time wasn’t changed."))
        } else {
            notice = String(localized: "Enter a time such as 9:30.")
            return
        }
        if written { unsaved = nil } else if isEnding { handBackUnsaved() }
    }

    @discardableResult
    private func write(_ date: Date, withTime: Bool) -> Bool {
        let text = withTime ? ItemDate.instant(date) : ItemDate.day(date, calendar: request.calendar)
        // A day chosen while a time is typed is the person's own change, so the time goes on it. A base the value has
        // already left stays, so the time is never written over a change the person did not see.
        let onBase = unsaved.map { $0.base == value } ?? false
        let taken = commit(.string(text), failure: String(localized: "The date couldn’t be saved."))
        if taken, onBase { unsaved?.base = value }
        if taken, unsaved == nil { shownValue = value }
        return taken
    }

    func clearDate() {
        // A time typed can't go on a date that is gone, and kept, it would set the date again as the panel closes.
        guard commit(nil, failure: String(localized: "The date couldn’t be saved.")) else { return }
        handBackUnsaved(reason: String(localized: "The date was cleared, so the time wasn’t set."))
        close()
    }
}
