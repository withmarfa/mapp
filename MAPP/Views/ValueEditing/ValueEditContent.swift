import Marfa
import SwiftUI

/// What a value panel, a menu-like popover and the designed panel all hold: the same rows for every kind, drawn with
/// the metrics the variant gives. A variant changes the surface and `ValueEditMetrics`, never this.
struct ValueEditContent: View {
    let model: ValueEditModel
    let metrics: ValueEditMetrics
    @Environment(\.interfaceTextSize) private var textSize
    @FocusState private var searchFocused: Bool

    private var scale: CGFloat { InterfaceStyle.scale(for: textSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.hasSearch { searchArea }
            listArea
            if let notice = model.notice { noticeArea(notice) }
        }
        .padding(metrics.padding * scale)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.measure(.total, $0) }
        .task {
            await Task.yield()
            searchFocused = true
        }
    }

    // MARK: Search

    @ViewBuilder private var searchArea: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            if model.kind == .tags, !model.heldTags.isEmpty {
                TagFlowLayout(spacing: 4 * scale) {
                    ForEach(model.heldTags, id: \.self) { tag in tagToken(tag) }
                }
            }
            HStack(spacing: 6 * scale) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(model.kind == .tags ? "Add or Find a Tag" : "Find or Add a Person", text: Bindable(model).query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityIdentifier("ValueEditSearch")
            }
            .padding(.horizontal, 8 * scale)
            .frame(height: metrics.rowHeight * scale)
            Divider()
        }
        .padding(.bottom, 4 * scale)
    }

    private func tagToken(_ tag: String) -> some View {
        HStack(spacing: 3 * scale) {
            Text(verbatim: tag).lineLimit(1)
            Button { model.removeTag(tag) } label: {
                Image(systemName: "xmark").font(.system(size: 8 * scale, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(tag)")
        }
        .font(.system(size: 11 * scale))
        .padding(.horizontal, 7 * scale)
        .padding(.vertical, 3 * scale)
        .background(.quaternary, in: .capsule)
    }

    // MARK: Rows

    @ViewBuilder private var listArea: some View {
        if case .date = model.kind {
            dateList
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
        }
    }

    /// The rows' own height until the room runs out, with a row's worth shown at the very least.
    private var scrollHeight: CGFloat {
        let wanted = model.rowsHeight > 0 ? model.rowsHeight : CGFloat(model.rows.count) * metrics.rowHeight * scale
        let chrome = max(0, model.totalHeight - model.listHeight)
        return min(wanted, max(model.maxHeight - chrome, metrics.rowHeight * scale))
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
                        .frame(maxWidth: .infinity, minHeight: metrics.headerHeight * scale, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                case .separator:
                    Divider().padding(.vertical, 5 * scale)
                case .option, .create:
                    ValueEditRow(row: row, model: model, metrics: metrics, scale: scale)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Date

    private var dateList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.rows) { row in ValueEditRow(row: row, model: model, metrics: metrics, scale: scale) }
            Divider().padding(.vertical, 5 * scale)
            DatePicker("Choose Date", selection: Binding {
                model.storedDate?.date ?? model.request.library.now()
            } set: { model.setDate($0) }, displayedComponents: model.hasTime ? [.date, .hourAndMinute] : [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("ItemPropertyDate.\(model.kind.field?.key ?? "")")
            if model.allowsTime {
                Toggle("Time", isOn: Binding { model.hasTime } set: { include in
                    model.setDate(model.storedDate?.date ?? model.request.library.now(), includingTime: include)
                })
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.horizontal, 8 * scale)
                .padding(.top, 4 * scale)
                .accessibilityIdentifier("ItemPropertyTime.\(model.kind.field?.key ?? "")")
            }
            HStack {
                Spacer()
                Button("Clear") { model.clearDate() }
                    .disabled(model.value == nil)
                    .accessibilityIdentifier("ItemPropertyClear.\(model.kind.field?.key ?? "")")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8 * scale)
            .padding(.top, 6 * scale)
            .padding(.bottom, 2 * scale)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            model.measure(.rows, height)
            model.measure(.list, height)
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
        }
    }
}

/// One option, person, tag or create line.
private struct ValueEditRow: View {
    let row: ValueListRow
    let model: ValueEditModel
    let metrics: ValueEditMetrics
    let scale: CGFloat

    private var isActive: Bool { model.activeRow == row.id }
    private var isAccent: Bool { isActive && (metrics.hoverIsAccent || model.activeIsKeyboard) }

    var body: some View {
        HStack(spacing: 7 * scale) {
            if metrics.hoverIsAccent {
                Image(systemName: "checkmark")
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .opacity(row.isCurrent ? 1 : 0)
                    .frame(width: 12 * scale)
                    .accessibilityHidden(true)
            }
            mark
            Text(verbatim: row.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8 * scale)
            if let detail = row.detail {
                Text(verbatim: detail)
                    .foregroundStyle(isAccent ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            if row.isCurrent, !metrics.hoverIsAccent {
                Image(systemName: "checkmark").font(.system(size: 11 * scale, weight: .semibold)).accessibilityHidden(true)
            }
        }
        .font(.system(size: metrics.textSize * scale))
        .foregroundStyle(isAccent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8 * scale)
        .frame(height: metrics.rowHeight * scale)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: metrics.rowRadius * scale, style: .continuous)
                    .fill(isAccent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            }
        }
        .contentShape(.rect)
        .onHover { model.hover($0 ? row.id : nil) }
        .onTapGesture { model.activate(row.id) }
        .id(row.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("ValueEditRow.\(row.id)")
    }

    @ViewBuilder private var mark: some View {
        switch row.mark {
        case .none:
            EmptyView()
        case .status(let group):
            StatusMark(mark: .init(group: group), size: 10 * scale)
        case .person(let initials):
            Text(verbatim: initials)
                .font(.system(size: 8 * scale, weight: .semibold))
                .frame(width: 18 * scale, height: 18 * scale)
                .background(.quaternary, in: .circle)
                .foregroundStyle(.primary)
        case .tag:
            Image(systemName: "tag").font(.system(size: 11 * scale)).foregroundStyle(isAccent ? .white : .secondary)
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 11 * scale)).foregroundStyle(isAccent ? .white : .secondary)
        }
    }
}
