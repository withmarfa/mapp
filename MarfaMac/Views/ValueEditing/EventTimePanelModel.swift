import Foundation
import Marfa
import Observation

/// The state of an event's time panel: which end a pick of a day is for, the time being typed, and the last write while
/// the library's copy may not show it yet. Every change is one edit of the properties that changed (`EventTime.changes`),
/// made from the time the item holds now, so a part the person did not change is never written over.
@MainActor @Observable
final class EventTimePanelModel {
    let spec: EventTime
    private let itemID: ItemID
    private let library: any ItemLibrary
    private let undoManager: UndoManager?
    private let mac: Calendar

    /// The end a calendar pick is for.
    var part: EventTime.Part = .start
    /// Why the last change was not made, in one line.
    var notice: String?

    /// A time being typed into a part's field, with the time the field showed when typing began.
    struct Typed {
        var text: String
        var base: String
    }
    var typed: [EventTime.Part: Typed] = [:]

    /// What the panel last wrote, shown while the library is still taking it.
    @ObservationIgnored private var pending: (reading: EventTime.Reading, mark: Int?)?
    private var writes = 0

    init(spec: EventTime, item: ItemID, library: any ItemLibrary, undoManager: UndoManager?, calendar: Calendar = .chosenWeekStart) {
        self.spec = spec
        itemID = item
        self.library = library
        self.undoManager = undoManager
        mac = calendar
    }

    var item: Item? { library.item(itemID) }

    var canEdit: Bool { item?.allows(.fields) ?? false }

    var now: Date { library.now() }

    /// The time the item holds, or the panel's own last write while that is on its way.
    var reading: EventTime.Reading {
        _ = writes
        guard let item else { return EventTime.Reading(start: nil, end: nil, allDay: false, zone: nil) }
        if let pending {
            let waiting = library.isWritingProperties(of: itemID) && !(pending.mark.map(library.tookPropertyWrite) ?? false)
            if waiting { return pending.reading }
            self.pending = nil
        }
        return spec.reading(of: item, mac: mac)
    }

    var calendar: Calendar { reading.calendar(mac: mac) }

    // MARK: Text

    func date(of part: EventTime.Part) -> Date? {
        let reading = reading
        return part == .start ? reading.start : reading.end
    }

    func dayText(of part: EventTime.Part) -> String? {
        guard let date = date(of: part) else { return nil }
        let calendar = calendar
        return date.formatted(Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated).year())
    }

    func timeText(of part: EventTime.Part) -> String {
        guard !reading.allDay, let date = date(of: part) else { return "" }
        return DateDisplay.timeOfDay(of: date, format: .stored(), calendar: calendar)
    }

    // MARK: Changing

    /// Writes the change from the time held to `new`, whole, in one edit; whether it was taken.
    @discardableResult
    private func apply(_ new: EventTime.Reading) -> Bool {
        guard canEdit, let item else { return false }
        let old = reading
        let changes = spec.changes(from: old, to: new, in: item, mac: mac)
        guard !changes.isEmpty else { return true }
        return write(changes, becoming: new)
    }

    private func write(_ changes: [String: PropertyValue?], becoming new: EventTime.Reading?) -> Bool {
        let before = library.lastPropertyWrite
        let taken = library.setItemProperties(itemID, changes: changes, actionName: String(localized: "Edit Time"), undoManager: undoManager)
        guard taken else {
            notice = item?.allows(.fields) == false ? PropertyLoss.notEditable.reason : String(localized: "The time couldn’t be saved.")
            return false
        }
        notice = nil
        let mark = library.lastPropertyWrite
        if let new { pending = (new, mark != before ? mark : nil) } else { pending = nil }
        writes += 1
        return true
    }

    private func attempt(_ change: () throws(EventTime.Refusal) -> EventTime.Reading) {
        do throws(EventTime.Refusal) {
            apply(try change())
        } catch {
            notice = error.message
        }
    }

    func choose(day: Date) {
        let (part, reading, mac) = (part, reading, mac)
        attempt { () throws(EventTime.Refusal) -> EventTime.Reading in try EventTime.choosing(day, for: part, in: reading, mac: mac) }
    }

    func setAllDay(_ on: Bool) {
        discardTyping()
        apply(EventTime.setting(allDay: on, in: reading, mac: mac, now: now))
    }

    func setZone(_ zone: TimeZone?) {
        var new = reading
        new.zone = zone
        apply(new)
    }

    /// Takes the start and the end away.
    func clear() {
        guard canEdit, let item else { return }
        discardTyping()
        let changes = spec.clearing(in: item)
        guard !changes.isEmpty else { return }
        _ = write(changes, becoming: EventTime.Reading(start: nil, end: nil, allDay: reading.allDay, zone: reading.zone))
    }

    // MARK: Typing

    func beginTyping(in which: EventTime.Part) {
        self.part = which
        if typed[which] == nil { typed[which] = Typed(text: timeText(of: which), base: timeText(of: which)) }
    }

    func type(_ text: String, into which: EventTime.Part) {
        let base = typed[which]?.base ?? timeText(of: which)
        typed[which] = Typed(text: text, base: base)
    }

    func shownTime(of which: EventTime.Part) -> String { typed[which]?.text ?? timeText(of: which) }

    private func discardTyping() { typed = [:] }

    /// Writes the time typed for `which`. Nothing is written where it is what the item holds, and a time typed against a
    /// time that has changed since is given back to the person, never written over the change.
    func commitTime(of which: EventTime.Part, isEnding: Bool = false) {
        guard let input = typed[which] else { return }
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == timeText(of: which) || text == input.base {
            typed[which] = nil
            return
        }
        guard canEdit else { return handBack(text, reason: PropertyLoss.notEditable.reason, of: which) }
        guard input.base == timeText(of: which) else {
            return handBack(text, reason: PropertyLoss.conflict.reason, of: which)
        }
        guard let time = TimeOfDay.parse(text) else {
            if isEnding { return handBack(text, reason: String(localized: "“\(text)” isn’t a time, so the time wasn’t changed."), of: which) }
            notice = String(localized: "Enter a time such as 9:30.")
            return
        }
        typed[which] = nil
        let (reading, mac, now) = (reading, mac, now)
        attempt { () throws(EventTime.Refusal) -> EventTime.Reading in
            try EventTime.setting(hour: time.hour, minute: time.minute, for: which, in: reading, mac: mac, now: now)
        }
    }

    private func handBack(_ text: String, reason: String, of which: EventTime.Part) {
        typed[which] = nil
        library.notices.notKept(String(localized: "Property Not Saved"), text: "\(String(localized: "Time")): \(text)", reason: reason)
    }

    /// The panel is ending: a time typed and not yet written is written, or handed back, unless the person cancelled.
    func finish(cancelled: Bool) {
        guard !cancelled else {
            typed = [:]
            return
        }
        for which in [EventTime.Part.start, .end] { commitTime(of: which, isEnding: true) }
    }
}
