import Marfa
import SwiftUI

/// What a value panel holds: the rows for the kind of value, drawn with `ValueEditMetrics`.
struct ValueEditContent: View {
    let model: ValueEditModel
    @Environment(\.interfaceTextSize) private var textSize
    @FocusState private var fieldFocused: Bool
    @FocusState private var timeFocused: Bool
    /// The height the chips and the field want, which the field is held to until eight lines of chips.
    @State private var chipsHeight: CGFloat = 0

    private var scale: CGFloat { InterfaceStyle.scale(for: textSize) }

    /// Eight lines of chips with the field's own padding.
    private var chipsLimit: CGFloat {
        (CGFloat(ValueEditMetrics.chipLines) * (ValueEditMetrics.fieldLine + 5) + 7) * scale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.hasSearch { searchArea }
            listArea
            if let type = model.typeToEditStatuses { editStatuses(type) }
            if let notice = model.notice { noticeArea(notice) }
        }
        .padding(ValueEditMetrics.padding * scale)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.measure(.total, $0) }
        .task {
            await Task.yield()
            fieldFocused = true
        }
        .onChange(of: model.listedCollections, initial: true) { _, ids in model.wantCounts(of: ids) }
        .onDisappear { model.releaseCounts() }
    }

    // MARK: Search

    @ViewBuilder private var searchArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Past eight lines of chips the field scrolls, so the list under it keeps its room.
            ScrollView {
                ChipFieldLayout(spacing: 5 * scale, lineHeight: ValueEditMetrics.fieldLine * scale, queryFloor: (model.query.isEmpty ? 16 : 48) * scale) {
                    ForEach(model.chips) { chip in
                        ValueChipView(chip: chip, scale: scale) { model.remove(chip) }
                    }
                    TextField(model.chips.isEmpty ? model.searchPrompt : "", text: Bindable(model).query)
                        .textFieldStyle(.plain)
                        .font(.system(size: ValueEditMetrics.textSize * scale))
                        .focused($fieldFocused)
                        .accessibilityLabel(model.searchPrompt)
                        .accessibilityIdentifier("ValueEditSearch")
                }
                .padding(.horizontal, 7 * scale)
                .padding(.top, 4 * scale)
                .padding(.bottom, 3 * scale)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chipsHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(chipsHeight, (ValueEditMetrics.fieldLine + 7) * scale), chipsLimit))
            Divider()
        }
        .padding(.bottom, 4 * scale)
    }

    // MARK: Rows

    @ViewBuilder private var listArea: some View {
        if case .date = model.kind {
            dateList
        } else if model.kind.isTyped {
            typedField
        } else {
            let height = scrollHeight
            ScrollViewReader { proxy in
                ScrollView {
                    rows
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.measure(.rows, $0) }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: height)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.measure(.list, $0) }
                .onChange(of: model.activeRow) { _, id in if let id, model.viaKeyboard { proxy.scrollTo(id) } }
            }
            .disabled(model.isSaving)
            .opacity(model.isSaving ? 0.5 : 1)
        }
    }

    /// The rows' own height until ten rows or the room run out, with a row's worth shown at the very least.
    private var scrollHeight: CGFloat {
        let rowsHeight = model.rowsHeight > 0 ? model.rowsHeight : CGFloat(model.rows.count) * ValueEditMetrics.rowHeight * scale
        let wanted = min(rowsHeight, model.listLimit(scale: scale))
        let chrome = max(0, model.totalHeight - model.listHeight)
        return min(wanted, max(model.maxHeight - chrome, ValueEditMetrics.rowHeight * scale))
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: ValueEditMetrics.rowGap * scale) {
            ForEach(model.rows) { row in
                switch row.role {
                case .header:
                    Text(verbatim: row.title)
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8 * scale)
                        .padding(.bottom, 2 * scale)
                        .frame(maxWidth: .infinity, minHeight: ValueEditMetrics.headerHeight * scale, alignment: .bottomLeading)
                        .accessibilityAddTraits(.isHeader)
                case .separator:
                    Divider().padding(.vertical, 3 * scale)
                case .option, .create:
                    ValueEditRow(row: row, model: model, scale: scale)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Edit Statuses

    /// A status panel ends with the way to the words themselves: the type's page in Settings > Types.
    private func editStatuses(_ type: TypeID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.vertical, 4 * scale)
            Button { model.editStatuses(of: type) } label: {
                Text("Edit Statuses…")
                    .font(.system(size: ValueEditMetrics.textSize * scale))
                    .padding(.horizontal, 8 * scale)
                    .frame(maxWidth: .infinity, minHeight: ValueEditMetrics.rowHeight * scale, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ValueEditEditStatuses")
        }
    }

    // MARK: Typed

    /// The field a text or a number is typed into. A text grows with what is typed and scrolls past eight lines.
    private var typedField: some View {
        let field = model.kind.field
        let isNumber = model.kind.isNumber
        return TextField(field?.label ?? "", text: Bindable(model).typed, prompt: Text("None"), axis: isNumber ? .horizontal : .vertical)
            .textFieldStyle(.plain)
            .lineLimit(isNumber ? 1...1 : 1...8)
            .font(.system(size: ValueEditMetrics.textSize * scale))
            .focused($fieldFocused)
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 4 * scale)
            .frame(maxWidth: .infinity, minHeight: ValueEditMetrics.rowHeight * scale, alignment: .leading)
            .appFocusRing(isFocused: fieldFocused)
            .accessibilityLabel(field?.label ?? "")
            .accessibilityIdentifier("ValueEditText")
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                model.measure(.rows, height)
                model.measure(.list, height)
            }
    }

    // MARK: Date

    private var dateKey: String { model.kind.field?.key ?? "" }

    private var dateList: some View {
        let calendar = model.request.calendar
        let now = model.request.library.now()
        return VStack(alignment: .leading, spacing: 0) {
            dayField
            VStack(alignment: .leading, spacing: ValueEditMetrics.rowGap * scale) {
                ForEach(model.rows.filter { $0.id != ValueEditOptions.notSetID }) { row in
                    ValueEditRow(row: row, model: model, scale: scale)
                }
            }
            Divider().padding(.vertical, 5 * scale)
            ValueCalendar(selected: model.storedDate?.date, today: now, calendar: calendar, scale: scale) { model.chooseDay($0) }
                .accessibilityIdentifier("ItemPropertyDate.\(dateKey)")
            if model.allowsTime { timeRows }
            Divider().padding(.vertical, 5 * scale)
            ForEach(model.rows.filter { $0.id == ValueEditOptions.notSetID }) { row in
                ValueEditRow(row: row, model: model, scale: scale)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            model.measure(.rows, height)
            model.measure(.list, height)
        }
    }

    /// The day typed, as the board draws it: "25 Nov 2026" with a bare caret above the quick days. A day typed there is set
    /// with Return; text that is no day stays with its reason.
    private var dayField: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: Binding { model.dayDraft ?? model.dayText } set: { model.dayDraft = $0 }, prompt: Text("Not Set"))
                .textFieldStyle(.plain)
                .font(.system(size: ValueEditMetrics.textSize * scale))
                .focused($fieldFocused)
                .onSubmit { model.commitDay(closing: true) }
                .onChange(of: fieldFocused) { _, focused in if focused { model.beginDay() } else { model.commitDay() } }
                .frame(minHeight: ValueEditMetrics.fieldLine * scale)
                .padding(.horizontal, 7 * scale)
                .padding(.top, 4 * scale)
                .padding(.bottom, 3 * scale)
                .accessibilityLabel("Date")
                .accessibilityIdentifier("ValueEditDay")
            Divider()
        }
        .padding(.bottom, 4 * scale)
    }

    /// The time as one narrow field, trailing its label. It reads as a placeholder until a time is set; typing a time sets
    /// one, and emptying the field takes it away again.
    @ViewBuilder private var timeRows: some View {
        Divider().padding(.vertical, 5 * scale)
        HStack(spacing: 8 * scale) {
            Text("Time")
            Spacer(minLength: 8 * scale)
            TextField("", text: Binding { model.timeDraft ?? model.timeText } set: { model.timeDraft = $0 })
                .textFieldStyle(.plain)
                .accessibilityLabel("Time")
                .multilineTextAlignment(.trailing)
                .focused($timeFocused)
                .onSubmit { model.commitTime() }
                .onChange(of: timeFocused) { _, focused in if focused { model.beginTime() } else { model.commitTime() } }
                .frame(width: 64 * scale)
                .padding(.horizontal, 6 * scale)
                .frame(height: 22 * scale)
                .background(.quaternary, in: .rect(cornerRadius: 5 * scale, style: .continuous))
                .appFocusRing(.rect(cornerRadius: 5 * scale, style: .continuous), isFocused: timeFocused)
                .overlay(alignment: .trailing) {
                    if (model.timeDraft ?? model.timeText).isEmpty {
                        Text(verbatim: "--:--").foregroundStyle(.tertiary).padding(.trailing, 6 * scale).allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier("ItemPropertyTimeField.\(dateKey)")
        }
        .font(.system(size: ValueEditMetrics.textSize * scale))
        .padding(.horizontal, 8 * scale)
        .frame(height: ValueEditMetrics.rowHeight * scale)
    }

    /// A conflict is a question, so it has no red: what happened, what that means, and two small buttons with Keep My Edit
    /// the main one. Anything else is one red line.
    @ViewBuilder private func noticeArea(_ notice: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.vertical, 4 * scale)
            if model.hasConflict {
                conflictFoot
            } else {
                Text(verbatim: notice)
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8 * scale)
                    .padding(.bottom, 2 * scale)
                    .accessibilityIdentifier("ValueEditNotice")
            }
        }
    }

    private var conflictFoot: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1 * scale) {
                Text(verbatim: ValueEditModel.conflictQuestion)
                    .foregroundStyle(.primary)
                Text(verbatim: ValueEditModel.conflictConsequence)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11 * scale))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8 * scale)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ValueEditNotice")
            HStack(spacing: 6 * scale) {
                Button("Keep My Edit") { model.keepEdit() }
                    .appButton(.primary, size: .small)
                    .accessibilityIdentifier("ValueEditKeepEdit")
                Button("Use Current Value") { model.useCurrentValue() }
                    .appButton(.secondary, size: .small)
                    .accessibilityIdentifier("ValueEditUseCurrent")
            }
            .padding(.horizontal, 8 * scale)
            .padding(.top, 6 * scale)
            .padding(.bottom, 4 * scale)
        }
    }
}

/// One option, person, tag or create line. Every row starts at the same edge: the lists keep no room for a tick.
private struct ValueEditRow: View {
    let row: ValueListRow
    let model: ValueEditModel
    let scale: CGFloat

    private var isActive: Bool { model.activeRow == row.id }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8 * scale) {
            ValueMarkView(mark: row.mark, scale: scale)
            Text(verbatim: row.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8 * scale)
            if row.role == .create {
                // The key cap shows only while Return takes this row.
                if isActive { ShortcutKeys("↩").layoutPriority(1) }
            } else if let detail = row.detail ?? model.countText(of: row) {
                Text(verbatim: detail)
                    .font(.system(size: 12 * scale))
                    .monospacedDigit()
                    .layoutPriority(1)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: ValueEditMetrics.textSize * scale))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8 * scale)
        .frame(height: ValueEditMetrics.rowHeight * scale)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: ValueEditMetrics.rowRadius * scale, style: .continuous)
                    .fill(SelectionLooks.chosen(for: scheme))
            }
        }
        .contentShape(.rect)
        .onHover { model.hover($0 ? row.id : nil) }
        .onTapGesture { model.activate(row.id) }
        .id(row.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.activate(row.id) }
        .accessibilityIdentifier("ValueEditRow.\(row.id)")
    }
}
