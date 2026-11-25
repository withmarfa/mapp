import SwiftUI

/// An event's time in one panel: a calendar that sets the day of the end that is chosen, the start and the end each with
/// its day and its time, All Day and the zone, then Not Set. Moving the start keeps the length. Every change is written at
/// once, as one edit.
struct EventTimePanelContent: View {
    let model: EventTimePanelModel
    let panel: ValueEditModel
    @Environment(\.interfaceTextSize) private var textSize
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focus: EventTime.Part?
    @FocusState private var dayFocused: Bool

    private var scale: CGFloat { InterfaceStyle.scale(for: textSize) }

    var body: some View {
        let reading = model.reading
        VStack(alignment: .leading, spacing: 0) {
            dayField
            ValueCalendar(
                selected: model.date(of: model.part) ?? model.date(of: .start), today: model.now, calendar: model.calendar, scale: scale
            ) { model.choose(day: $0) }
            .padding(.top, 4 * scale)
            .accessibilityIdentifier("EventTimeCalendar")
            Divider().padding(.vertical, 5 * scale)
            partRow(String(localized: "Starts"), .start, reading: reading)
            if model.spec.end != nil { partRow(String(localized: "Ends"), .end, reading: reading) }
            if model.spec.allDay != nil { allDayRow(reading) }
            if model.spec.zone != nil, !reading.allDay { zoneRow(reading) }
            Divider().padding(.vertical, 5 * scale)
            notSetRow
            if let notice = model.notice { noticeLine(notice) }
        }
        .font(.system(size: ValueEditMetrics.textSize * scale))
        .padding(ValueEditMetrics.padding * scale)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            panel.measure(.total, height)
            panel.measure(.rows, 0)
            panel.measure(.list, 0)
        }
        .disabled(!model.canEdit)
        .task {
            await Task.yield()
            dayFocused = true
        }
    }

    // MARK: Day

    /// The day of the chosen end, typed: "26 Nov 2026" with a bare caret. Return sets it.
    private var dayField: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: Binding { model.shownDay } set: { model.typeDay($0) }, prompt: Text("None"))
                .textFieldStyle(.plain)
                .focused($dayFocused)
                .onSubmit { model.commitDay() }
                .onChange(of: dayFocused) { _, focused in if focused { model.beginDay() } else { model.commitDay() } }
                .frame(minHeight: ValueEditMetrics.fieldLine * scale)
                .padding(.horizontal, 7 * scale)
                .padding(.top, 4 * scale)
                .padding(.bottom, 3 * scale)
                .accessibilityLabel("Date")
                .accessibilityIdentifier("EventTimeDayField")
            Divider()
        }
        .padding(.bottom, 4 * scale)
    }

    // MARK: Parts

    private func partRow(_ title: String, _ part: EventTime.Part, reading: EventTime.Reading) -> some View {
        HStack(spacing: 6 * scale) {
            Text(verbatim: title)
            Spacer(minLength: 8 * scale)
            dayChip(part)
            if !reading.allDay { timeChip(part) }
        }
        .padding(.horizontal, 8 * scale)
        .frame(height: ValueEditMetrics.rowHeight * scale)
    }

    private func dayChip(_ part: EventTime.Part) -> some View {
        let chosen = model.part == part
        let text = model.dayText(of: part)
        return Button { model.part = part } label: {
            Text(verbatim: text ?? String(localized: "None"))
                .monospacedDigit()
                .foregroundStyle(text == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .padding(.horizontal, 9 * scale)
                .frame(height: 24 * scale)
                .background(ChipLooks.current.chipWash(for: scheme), in: .rect(cornerRadius: 7 * scale, style: .continuous))
                .overlay { if chosen { RoundedRectangle(cornerRadius: 7 * scale, style: .continuous).strokeBorder(.primary.opacity(0.3), lineWidth: 1.5) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(part == .start ? Text("Start Day") : Text("End Day"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("EventTimeDay.\(part == .start ? "start" : "end")")
    }

    private func timeChip(_ part: EventTime.Part) -> some View {
        let text = Binding { model.shownTime(of: part) } set: { model.type($0, into: part) }
        return TextField("", text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .focused($focus, equals: part)
            .onSubmit { model.commitTime(of: part) }
            .onChange(of: focus) { old, new in
                if new == part { model.beginTyping(in: part) } else if old == part { model.commitTime(of: part) }
            }
            .frame(width: 52 * scale)
            .padding(.horizontal, 5 * scale)
            .frame(height: 24 * scale)
            .background(ChipLooks.current.chipWash(for: scheme), in: .rect(cornerRadius: 7 * scale, style: .continuous))
            .appFocusRing(.rect(cornerRadius: 7 * scale, style: .continuous), isFocused: focus == part)
            .overlay {
                if model.shownTime(of: part).isEmpty { Text(verbatim: "--:--").foregroundStyle(.tertiary).allowsHitTesting(false) }
            }
            .accessibilityLabel(part == .start ? Text("Start Time") : Text("End Time"))
            .accessibilityIdentifier("EventTimeClock.\(part == .start ? "start" : "end")")
    }

    // MARK: All Day and zone

    private func allDayRow(_ reading: EventTime.Reading) -> some View {
        HStack(spacing: 8 * scale) {
            Text("All Day")
            Spacer(minLength: 8 * scale)
            Toggle("All Day", isOn: Binding { reading.allDay } set: { model.setAllDay($0) })
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityIdentifier("EventTimeAllDay")
        }
        .padding(.horizontal, 8 * scale)
        .frame(height: ValueEditMetrics.rowHeight * scale)
    }

    private func zoneRow(_ reading: EventTime.Reading) -> some View {
        let held = reading.zone?.identifier ?? ""
        return HStack(spacing: 8 * scale) {
            Text("Time Zone")
            Spacer(minLength: 8 * scale)
            Picker("Time Zone", selection: Binding {
                held
            } set: { model.setZone($0.isEmpty ? nil : TimeZone(identifier: $0)) }) {
                Text("Not Set").tag("")
                if !held.isEmpty, !Self.zones.contains(where: { $0.id == held }) { Text(verbatim: held).tag(held) }
                ForEach(Self.zones, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("EventTimeZone")
        }
        .padding(.horizontal, 8 * scale)
        .frame(height: ValueEditMetrics.rowHeight * scale)
    }

    /// The zones the menu offers, by the city each is named for.
    private static let zones: [(id: String, name: String)] = TimeZone.knownTimeZoneIdentifiers
        .compactMap { id in TimeZone(identifier: id).map { (id, EventTime.name(of: $0)) } }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    // MARK: Foot

    private var notSetRow: some View {
        Button { model.clear() } label: {
            Text("Not Set")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8 * scale)
                .frame(height: ValueEditMetrics.rowHeight * scale)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("EventTimeNotSet")
    }

    private func noticeLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11 * scale))
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8 * scale)
            .padding(.top, 2 * scale)
            .accessibilityIdentifier("EventTimeNotice")
    }
}
