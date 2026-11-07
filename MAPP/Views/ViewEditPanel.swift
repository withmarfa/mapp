import SwiftUI

/// The right sidebar while a view is edited (`ViewPanel`): its name, layout, filters, sort, group, and the table's columns or the gallery's cards. Each
/// change shows at once in the window beside it, and none is kept until Save (`ViewPanelToolbar`). A type's list and
/// the other places that can become a view get the same panel without a name, and offer Save as View.
struct ViewEditPanel: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel
    @FocusState private var nameFocused: Bool

    var body: some View {
        let content = browser.tableContent(in: library)
        ScrollView {
            VStack(alignment: .leading, spacing: InspectorMetrics.sectionGap) {
                ViewPanelNotes(browser: browser, panel: panel)
                if panel.purpose != .place {
                    ViewPanelSection(title: "Name") {
                        InspectorBox {
                            TextField("View Name", text: $panel.shownName)
                                .textFieldStyle(.plain)
                                .focused($nameFocused)
                                .onSubmit { SavedViews.save(browser, in: library, order: order) }
                                .accessibilityIdentifier("ViewPanelName")
                        }
                    }
                }
                ViewPanelLayoutSection(browser: browser, panel: panel)
                ViewPanelFilters(browser: browser, panel: panel, content: content)
                ViewPanelSort(browser: browser, content: content)
                ViewPanelGroup(browser: browser, content: content)
                if browser.viewMode == .table {
                    ViewPanelColumns(browser: browser, panel: panel, content: content)
                } else if browser.viewMode == .gallery {
                    ViewPanelCards(browser: browser, panel: panel, content: content)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .modifier(ViewSaveConfirmation(browser: browser, panel: panel))
        .task(id: ObjectIdentifier(panel)) {
            if panel.isNew { nameFocused = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewEditPanel")
    }
}

/// A section's heading, with a note beside it such as where its choices are kept, above its grouped box.
struct ViewPanelSection<Content: View>: View {
    let title: LocalizedStringKey
    var note: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            HStack(spacing: 6) {
                Text(title).interfaceFont(.body.weight(.semibold))
                Spacer(minLength: 0)
                if let note {
                    Text(note).interfaceFont(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, InspectorMetrics.headingInset)
            .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// The layouts the place offers, as tiles. The choice is the window's, held for a view until Save.
private struct ViewPanelLayoutSection: View {
    @CurrentLibrary private var library
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    let panel: ViewPanel

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        ViewPanelSection(title: "Layout", note: panel.purpose == .place ? nil : "This Mac") {
            HStack(spacing: 6) {
                ForEach(browser.availableViewModes(in: library), id: \.self) { mode in
                    let isSelected = browser.viewMode == mode
                    Button {
                        browser.viewMode = mode
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mode.symbol).font(.system(size: 15 * scale))
                            Text(mode.title).font(.system(size: 10.5 * scale)).lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .fontWeight(isSelected ? .medium : .regular)
                        .frame(maxWidth: .infinity, minHeight: 46 * scale)
                        .background(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("ViewPanelLayout.\(mode.rawValue)")
                }
            }
        }
    }
}

/// Group by, and for a board or a timeline the field it is laid out by. Hide Empty Groups is a saved view's choice for
/// its board.
private struct ViewPanelGroup: View {
    @CurrentLibrary private var library
    let browser: Browser
    let content: ItemTableContent

    var body: some View {
        ViewPanelSection(title: "Group") {
            InspectorBox {
                HStack {
                    Text("Group by")
                    Spacer(minLength: 0)
                    picker
                }
                if case .view(let id) = browser.item {
                    Toggle("Hide Empty Groups", isOn: Binding {
                        browser.macSettings(for: id).hidesEmptyGroups
                    } set: { hides in
                        browser.changeViewSettings(id) { $0.hidesEmptyGroups = hides }
                    })
                    .disabled(browser.viewMode != .board)
                    .help(browser.viewMode == .board ? "" : String(localized: "Only a board has empty groups."))
                    .accessibilityIdentifier("ViewPanelHideEmptyGroups")
                }
            }
        }
    }

    @ViewBuilder private var picker: some View {
        let place = browser.item
        switch browser.viewMode {
        case .board:
            let fields = browser.boardFieldChoices(in: library)
            let selected = ItemBoardLayout.selectedField(browser.boardFieldKey(in: place), available: fields)
            Picker("Group by", selection: Binding { selected?.key ?? "" } set: { browser.setBoardField($0, in: place) }) {
                ForEach(fields) { Text($0.label).tag($0.key) }
            }
            .labelsHidden()
            .accessibilityIdentifier("ViewPanelGroupBy")
        case .timeline:
            let fields = browser.timelineFieldChoices(in: library)
            let selected = ItemTimelineLayout.selectedField(browser.timelineFields[place], fields: fields)
            Picker("Group by", selection: Binding { selected ?? "" } set: { browser.timelineFields[place] = $0 }) {
                ForEach(fields, id: \.key) { Text($0.label).tag($0.key) }
            }
            .labelsHidden()
            .accessibilityIdentifier("ViewPanelGroupBy")
        default:
            Picker("Group by", selection: Binding { content.grouping?.id ?? "" } set: { id in
                browser.tableOptions[place, default: .init()].grouping = id.isEmpty ? .none : .column(id)
                browser.tableOptions[place, default: .init()].collapsed = nil
            }) {
                Text("None").tag("")
                Divider()
                ForEach(content.categoricalColumns) { Text($0.label).tag($0.id) }
            }
            .labelsHidden()
            .accessibilityIdentifier("ViewPanelGroupBy")
        }
    }
}

extension ItemViewMode {
    /// The layout's name on its tile.
    var title: String {
        switch self {
        case .list: String(localized: "List")
        case .gallery: String(localized: "Gallery")
        case .table: String(localized: "Table")
        case .board: String(localized: "Board")
        case .timeline: String(localized: "Timeline")
        }
    }
}
