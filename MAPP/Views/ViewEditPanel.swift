import SwiftUI

/// The right sidebar while a view is edited (`ViewPanel`): its name, how it is shown, sort, group, and the table's
/// columns or the gallery's cards. Each change shows at once in the window beside it and, in a saved view, is written
/// as it is made; Done closes the panel (`ViewPanelToolbar`). Filters are not here: they live in the row above the list
/// (`FilterChips`). A type's list and the other places that can become a view get the same panel without a name, and
/// offer Save as View. A Rows section for the list comes after the list's rows do.
struct ViewEditPanel: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    @Bindable var browser: Browser
    @Bindable var panel: ViewPanel
    @FocusState private var nameFocused: Bool

    var body: some View {
        let content = browser.tableContent(in: library)
        let arrangement = SavedViews.arrangement(browser, content: content, order: order)
        ScrollView {
            VStack(alignment: .leading, spacing: InspectorMetrics.sectionGap) {
                if panel.purpose != .place {
                    ViewPanelSection(title: "Name") {
                        InspectorBox {
                            TextField("View Name", text: $panel.shownName)
                                .textFieldStyle(.plain)
                                .focused($nameFocused)
                                .onSubmit { submitName() }
                                .accessibilityIdentifier("ViewPanelName")
                        }
                    }
                }
                ViewPanelLayoutSection(browser: browser, panel: panel)
                ViewPanelSort(browser: browser, content: content, sort: arrangement.sort)
                ViewPanelGroup(browser: browser, content: content, arrangement: arrangement)
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
        .task(id: ObjectIdentifier(panel)) {
            if panel.isNew { nameFocused = true }
        }
        // A name is written when the person commits it: Return, or leaving the field.
        .onChange(of: nameFocused) { if !nameFocused, panel.viewID != nil { commitName() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewEditPanel")
    }

    private func submitName() {
        if panel.isNew {
            Task { await browser.finishViewPanel(in: library, order: order) }
        } else {
            commitName()
        }
    }

    private func commitName() {
        Task { await browser.commitViewName(of: panel, in: library) }
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

/// The layout the window shows the place in, as a pop-up named Show As with the layout's symbol and name. The choice is
/// the window's, and this Mac keeps a saved view's as it is made.
private struct ViewPanelLayoutSection: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    let panel: ViewPanel

    var body: some View {
        ViewPanelSection(title: "Layout", note: panel.purpose == .place ? nil : "This Mac") {
            InspectorBox {
                HStack {
                    Text("Show As")
                    Spacer(minLength: 0)
                    Picker("Show As", selection: $browser.viewMode) {
                        ForEach(browser.availableViewModes(in: library), id: \.self) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityIdentifier("ViewPanelLayout")
                }
            }
        }
    }
}

/// Group by, and for a board or a timeline the field it is laid out by. Hide Empty Groups is a saved view's choice for
/// its board.
private struct ViewPanelGroup: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser
    let content: ItemTableContent
    let arrangement: SavedViews.Arrangement

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
            Picker("Group by", selection: Binding { Self.tag(of: arrangement.grouping) } set: { setGrouping($0) }) {
                Text("None").tag("")
                if arrangement.isDated, order.groupsByDate {
                    Text("Date").tag(Self.dateTag)
                }
                Divider()
                ForEach(content.categoricalColumns) { Text($0.label).tag($0.id) }
            }
            .labelsHidden()
            .accessibilityIdentifier("ViewPanelGroupBy")
        }
    }

    private static let dateTag = "\u{0}date"

    private static func tag(of grouping: SavedViews.ShownGrouping) -> String {
        switch grouping {
        case .none: ""
        case .date: dateTag
        case .column(let id): id
        }
    }

    /// Groups the layout. A list that sorts by date and groups by it is put back to that by clearing its sort and
    /// grouping; asking it for no groups sorts it by what it showed, which is what stops the date sections.
    private func setGrouping(_ tag: String) {
        let place = browser.item
        var options = browser.tableOptions[place] ?? ItemTableOptions()
        if tag == Self.dateTag {
            options.grouping = .automatic
            options.sort = nil
        } else if tag.isEmpty {
            options.grouping = .none
            if arrangement.isDated { options.sort = arrangement.sort }
        } else {
            options.grouping = .column(tag)
        }
        options.collapsed = nil
        browser.tableOptions[place] = options
    }
}

extension ItemViewMode {
    /// The layout's name.
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
