import Marfa
import SwiftUI

/// What a value panel holds: the rows for the kind of value, drawn with `ValueEditMetrics`.
struct ValueEditContent: View {
    let model: ValueEditModel
    @Environment(\.interfaceTextSize) private var textSize
    @FocusState private var fieldFocused: Bool

    private var scale: CGFloat { InterfaceStyle.scale(for: textSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.hasSearch { searchArea }
            listArea
            if let notice = model.notice { noticeArea(notice) }
        }
        .padding(ValueEditMetrics.padding * scale)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.measure(.total, $0) }
        .task {
            await Task.yield()
            fieldFocused = true
        }
    }

    // MARK: Search

    @ViewBuilder private var searchArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChipFieldLayout(spacing: 4 * scale, lineHeight: ValueEditMetrics.rowHeight * scale) {
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
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 2 * scale)
            Divider().padding(.top, 2 * scale)
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

    /// The rows' own height until the room runs out, with a row's worth shown at the very least.
    private var scrollHeight: CGFloat {
        let wanted = model.rowsHeight > 0 ? model.rowsHeight : CGFloat(model.rows.count) * ValueEditMetrics.rowHeight * scale
        let chrome = max(0, model.totalHeight - model.listHeight)
        return min(wanted, max(model.maxHeight - chrome, ValueEditMetrics.rowHeight * scale))
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.rows) { row in
                switch row.role {
                case .header:
                    Text(verbatim: row.title)
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8 * scale)
                        .frame(maxWidth: .infinity, minHeight: ValueEditMetrics.headerHeight * scale, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                case .separator:
                    Divider().padding(.vertical, 5 * scale)
                case .option, .create:
                    ValueEditRow(row: row, model: model, scale: scale)
                }
            }
        }
        .accessibilityElement(children: .contain)
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
            ForEach(model.rows.filter { $0.id != ValueEditOptions.notSetID }) { row in
                ValueEditRow(row: row, model: model, scale: scale)
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

    /// The Time switch, and, once it is on, the time as the system's narrow field with its stepper.
    @ViewBuilder private var timeRows: some View {
        Divider().padding(.vertical, 5 * scale)
        Toggle(isOn: Binding { model.hasTime } set: { model.setIncludesTime($0) }) {
            Text("Time")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: ValueEditMetrics.textSize * scale))
        .padding(.horizontal, 8 * scale)
        .frame(height: ValueEditMetrics.rowHeight * scale)
        .accessibilityIdentifier("ItemPropertyTime.\(dateKey)")
        if model.hasTime {
            DatePicker("Time", selection: Binding {
                model.storedDate?.date ?? model.request.library.now()
            } set: { model.setDate($0) }, displayedComponents: [.hourAndMinute])
                .datePickerStyle(.stepperField)
                .labelsHidden()
                .fixedSize()
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 2 * scale)
                .accessibilityIdentifier("ItemPropertyTimeField.\(dateKey)")
        }
    }

    private func noticeArea(_ notice: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.vertical, 4 * scale)
            Text(verbatim: notice)
                .font(.system(size: 11 * scale))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8 * scale)
                .padding(.bottom, 2 * scale)
                .accessibilityIdentifier("ValueEditNotice")
            if model.hasConflict {
                HStack(spacing: 12 * scale) {
                    Button("Keep My Edit") { model.keepEdit() }
                        .accessibilityIdentifier("ValueEditKeepEdit")
                    Button("Use Current Value") { model.useCurrentValue() }
                        .accessibilityIdentifier("ValueEditUseCurrent")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11 * scale))
                .padding(.horizontal, 8 * scale)
                .padding(.bottom, 2 * scale)
            }
        }
    }
}

/// One option, person, tag or create line. Every row starts at the same edge: the lists keep no room for a tick.
private struct ValueEditRow: View {
    let row: ValueListRow
    let model: ValueEditModel
    let scale: CGFloat

    private var isActive: Bool { model.activeRow == row.id }

    var body: some View {
        HStack(spacing: 7 * scale) {
            ValueMarkView(mark: row.mark, scale: scale, onAccent: isActive)
            Text(verbatim: row.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8 * scale)
            if let detail = row.detail {
                Text(verbatim: detail)
                    .foregroundStyle(isActive ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
        }
        .font(.system(size: ValueEditMetrics.textSize * scale))
        .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8 * scale)
        .frame(height: ValueEditMetrics.rowHeight * scale)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: ValueEditMetrics.rowRadius * scale, style: .continuous)
                    .fill(Color.accentColor)
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
